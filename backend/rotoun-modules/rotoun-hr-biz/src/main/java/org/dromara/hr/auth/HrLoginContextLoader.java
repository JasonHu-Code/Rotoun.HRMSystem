package org.dromara.hr.auth;

import cn.dev33.satoken.SaManager;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.dromara.common.redis.utils.RedisUtils;
import org.dromara.hr.datascope.HrDataScopeRule;
import org.dromara.hr.datascope.HrDataScopeType;
import org.dromara.hr.datascope.HrLoginContext;
import org.dromara.hr.domain.DataScopeRuleEntity;
import org.dromara.hr.domain.Employee;
import org.dromara.hr.domain.Employment;
import org.dromara.hr.domain.Organization;
import org.dromara.hr.domain.vo.RoleRef;
import org.dromara.hr.mapper.DataScopeRuleMapper;
import org.dromara.hr.mapper.EmployeeMapper;
import org.dromara.hr.mapper.EmploymentMapper;
import org.dromara.hr.mapper.HrAuthLookupMapper;
import org.dromara.hr.mapper.OrganizationMapper;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 装配 {@link HrLoginContext}：登录账号 → 员工 → 主岗 → 组织 → 角色 → 数据权限规则。
 *
 * <p>为什么缓存整份上下文而不是每次查库：数据权限拦截器在<b>每条</b>业务 SQL 前都要读它，
 * 一次列表请求可能触发十几次查询。装配一次缓存 8 小时（与 token 有效期同量级），
 * 调岗/改角色时主动清 key（{@link #evict(Long)}），比每次 JOIN 五张表便宜得多。
 *
 * <p>装配失败（员工档案缺失、主岗缺失、组织被删）一律<b>不抛异常</b>：登录要能用，
 * 但权限只能收窄不能放宽——缺什么就少一条规则，最终由 {@code HrDataScopeSqlBuilder} 落到
 * {@code 1 = 0}。这条底线不能因为"怕报错"而改成放行。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class HrLoginContextLoader {

    /** Redis 键前缀：hr:login:{userId} */
    public static final String CACHE_KEY_PREFIX = "hr:login:";

    /** 取不到 token 有效期时的兜底（与 Sa-Token timeout 默认一致） */
    private static final long DEFAULT_TTL_SECONDS = 8 * 60 * 60L;

    private final EmployeeMapper employeeMapper;
    private final EmploymentMapper employmentMapper;
    private final OrganizationMapper organizationMapper;
    private final DataScopeRuleMapper dataScopeRuleMapper;
    private final HrAuthLookupMapper authLookupMapper;

    /**
     * 取上下文：先读缓存，未命中再装配并回写。
     */
    public HrLoginContext getOrLoad(Long userId) {
        if (userId == null) {
            return null;
        }
        String key = cacheKey(userId);
        HrLoginContext cached = RedisUtils.getCacheObject(key);
        if (cached != null) {
            return cached;
        }
        HrLoginContext ctx = load(userId);
        RedisUtils.setCacheObject(key, ctx, Duration.ofSeconds(ttlSeconds()));
        return ctx;
    }

    /**
     * 全量装配（不走缓存）。装配过程中任何一步查不到都只降级、不中断。
     */
    public HrLoginContext load(Long userId) {
        HrLoginContext ctx = new HrLoginContext();
        ctx.setUserId(userId);

        // 1. 角色
        List<RoleRef> roles = authLookupMapper.selectRolesByUserId(userId);
        Set<String> roleCodes = roles.stream()
            .map(RoleRef::getRoleKey)
            .filter(code -> code != null && !code.isBlank())
            .collect(Collectors.toCollection(LinkedHashSet::new));
        ctx.setRoleCodes(roleCodes);
        Set<Long> roleIds = roles.stream().map(RoleRef::getRoleId).collect(Collectors.toSet());

        // 2. 账号 → 员工（可能没有：纯管理员）
        Long employeeId = employeeMapper.selectIdBySysUserId(userId);
        if (employeeId != null) {
            ctx.setEmployeeId(employeeId);
            fillPrimaryEmployment(ctx, employeeId);
        } else {
            log.info("[HR上下文] 账号未绑定员工档案（纯管理员或未建账号）：userId={}, roles={}", userId, roleCodes);
        }

        // 3. 角色 → 数据权限规则
        if (!roleIds.isEmpty()) {
            ctx.setScopeRules(loadRules(roleIds));
        }
        boolean canExport = ctx.getScopeRules().stream().anyMatch(r -> Boolean.TRUE.equals(r.getCanExport()));
        ctx.setCanExport(canExport);

        if (ctx.getScopeRules().isEmpty()) {
            log.warn("[HR上下文] 账号没有任何数据权限规则，业务数据将全部不可见：userId={}, roles={}", userId, roleCodes);
        }
        return ctx;
    }

    /**
     * 主岗：只看 is_current=1 且 employment_type=PRIMARY 的那一条。
     * 兼岗不参与数据权限判定——兼任两个部门的人，其数据范围由角色规则决定，不由岗位数决定。
     */
    private void fillPrimaryEmployment(HrLoginContext ctx, Long employeeId) {
        Employment primary = employmentMapper.selectOne(
            new LambdaQueryWrapper<Employment>()
                .eq(Employment::getEmployeeId, employeeId)
                .eq(Employment::getIsCurrent, Boolean.TRUE)
                .eq(Employment::getEmploymentType, "PRIMARY")
                .orderByDesc(Employment::getStartDate)
                .last("LIMIT 1")
        );
        if (primary == null) {
            log.warn("[HR上下文] 员工没有当前主岗任职，组织/法人字段为空：employeeId={}", employeeId);
            return;
        }
        ctx.setOrganizationId(primary.getOrganizationId());
        ctx.setLegalEntityId(primary.getLegalEntityId());
        ctx.setPositionId(primary.getPositionId());

        Organization org = primary.getOrganizationId() == null
            ? null : organizationMapper.selectById(primary.getOrganizationId());
        if (org != null) {
            ctx.setOrgPath(org.getOrgPath());
        } else if (primary.getOrganizationId() != null) {
            log.warn("[HR上下文] 主岗组织不存在或已删除：employeeId={}, organizationId={}",
                employeeId, primary.getOrganizationId());
        }
    }

    /**
     * 规则落库格式 → 运行期模型，并把 ORG_TREE 的组织 ID 解析成路径前缀。
     *
     * <p>为什么在这里解析：{@code org_path} 只在 organization 表里，而规则会被高频繁读；
     * 解析一次随上下文缓存，SQL 生成阶段就只剩字符串拼接，能脱离 Spring 单测。
     */
    private List<HrDataScopeRule> loadRules(Set<Long> roleIds) {
        List<DataScopeRuleEntity> rows = dataScopeRuleMapper.selectList(
            new LambdaQueryWrapper<DataScopeRuleEntity>().in(DataScopeRuleEntity::getRoleId, roleIds)
        );
        Map<Long, String> pathCache = resolveOrgPaths(rows);

        List<HrDataScopeRule> rules = new ArrayList<>(rows.size());
        for (DataScopeRuleEntity row : rows) {
            HrDataScopeRule rule = new HrDataScopeRule();
            rule.setId(row.getId());
            rule.setRoleId(row.getRoleId());
            rule.setScopeType(row.getScopeType());
            rule.setScopeValue(row.getScopeValue());
            rule.setCanExport(row.getCanExport());

            if (HrDataScopeType.ORG_TREE == HrDataScopeType.of(row.getScopeType())) {
                Long orgId = parseId(row.getScopeValue());
                String path = orgId == null ? null : pathCache.get(orgId);
                if (path == null) {
                    // 前缀缺失：SqlBuilder 会跳过这条规则；若一条都不剩，最终落到 1=0
                    log.warn("[HR上下文] ORG_TREE 规则找不到组织路径，该规则不生效：roleId={}, scopeValue={}",
                        row.getRoleId(), row.getScopeValue());
                } else {
                    rule.setPathPrefix(path);
                }
            }
            rules.add(rule);
        }
        return rules;
    }

    /**
     * 一次性把 ORG_TREE 用到的组织路径捞出来，避免 N 次单条查询。
     */
    private Map<Long, String> resolveOrgPaths(List<DataScopeRuleEntity> rows) {
        Set<Long> orgIds = new HashSet<>();
        for (DataScopeRuleEntity row : rows) {
            if (HrDataScopeType.ORG_TREE == HrDataScopeType.of(row.getScopeType())) {
                Long id = parseId(row.getScopeValue());
                if (id != null) {
                    orgIds.add(id);
                }
            }
        }
        if (orgIds.isEmpty()) {
            return Map.of();
        }
        Map<Long, String> map = new HashMap<>(orgIds.size());
        for (Organization org : organizationMapper.selectByIds(orgIds)) {
            map.put(org.getId(), org.getOrgPath());
        }
        return map;
    }

    /**
     * 清缓存。调岗、改角色、组织移动后必须调用，否则最长要等 8 小时才生效。
     */
    public void evict(Long userId) {
        if (userId != null) {
            RedisUtils.deleteObject(cacheKey(userId));
        }
    }

    public String cacheKey(Long userId) {
        return CACHE_KEY_PREFIX + userId;
    }

    /**
     * 缓存时长跟 token 一致：token 还在、上下文却被清掉，会导致"登录着但看不到数据"的怪状态。
     */
    private long ttlSeconds() {
        try {
            long timeout = SaManager.getConfig().getTimeout();
            return timeout > 0 ? timeout : DEFAULT_TTL_SECONDS;
        } catch (Exception e) {
            return DEFAULT_TTL_SECONDS;
        }
    }

    private Long parseId(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        try {
            long id = Long.parseLong(raw.trim());
            return id > 0 ? id : null;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /**
     * 员工实体只用于取 id，这里包一层避免调用方直接依赖 Mapper。
     */
    public Employee findEmployeeByUserId(Long userId) {
        Long id = employeeMapper.selectIdBySysUserId(userId);
        return id == null ? null : employeeMapper.selectById(id);
    }
}
