package org.dromara.hr.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.dromara.hr.auth.HrLoginContextLoader;
import org.dromara.hr.datascope.HrDataScopeException;
import org.dromara.hr.datascope.HrDataScopeType;
import org.dromara.hr.domain.DataScopeRuleEntity;
import org.dromara.hr.domain.Organization;
import org.dromara.hr.domain.dto.HrDataScopeRuleDTO;
import org.dromara.hr.domain.vo.HrDataScopeOptionsVO;
import org.dromara.hr.domain.vo.HrDataScopeRuleVO;
import org.dromara.hr.domain.vo.IdNameOption;
import org.dromara.hr.mapper.DataScopeRuleMapper;
import org.dromara.hr.mapper.HrAuthLookupMapper;
import org.dromara.hr.mapper.HrOptionMapper;
import org.dromara.hr.mapper.OrganizationMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

/**
 * 数据权限规则维护。
 *
 * <p>三条业务约束写死在服务层，页面上配不出来：
 * <ol>
 *     <li><b>ALL 不能与其它范围共存</b>：ALL 已经包含全部，再配 ORG 只会让人以为"范围被收窄了"；</li>
 *     <li><b>COMPANY/ORG/ORG_TREE 必须指向存在的法人/组织</b>：否则规则运行期直接失效，
 *         表现为"这个人什么都看不到"，排查成本极高；</li>
 *     <li><b>保存后必须清缓存</b>：登录上下文缓存 8 小时，不清就是"改了权限没反应"。</li>
 * </ol>
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class HrDataScopeRuleService {

    /** 单角色规则条数上限：正常最多 2~3 条，超过基本是误操作 */
    private static final int MAX_RULES_PER_ROLE = 10;

    private final DataScopeRuleMapper ruleMapper;
    private final OrganizationMapper organizationMapper;
    private final HrAuthLookupMapper authLookupMapper;
    private final HrOptionMapper optionMapper;
    private final HrLoginContextLoader contextLoader;

    /**
     * 某角色的全部规则。
     */
    public List<HrDataScopeRuleVO> list(Long roleId) {
        List<DataScopeRuleEntity> rows = ruleMapper.selectList(
            new LambdaQueryWrapper<DataScopeRuleEntity>()
                .eq(DataScopeRuleEntity::getRoleId, roleId)
                .orderByAsc(DataScopeRuleEntity::getId)
        );
        List<HrDataScopeRuleVO> vos = new ArrayList<>(rows.size());
        for (DataScopeRuleEntity row : rows) {
            HrDataScopeRuleVO vo = new HrDataScopeRuleVO();
            vo.setId(row.getId());
            vo.setRoleId(row.getRoleId());
            vo.setScopeType(row.getScopeType());
            vo.setScopeValue(row.getScopeValue());
            vo.setCanExport(row.getCanExport());
            vo.setRemark(row.getRemark());
            vo.setScopeName(resolveName(row.getScopeType(), row.getScopeValue()));
            vos.add(vo);
        }
        return vos;
    }

    /**
     * 配置页的下拉数据。组织还没导入时返回空列表 + 标记，前端据此提示"先导入组织架构"，
     * 而不是给一个能点但没选项的下拉让人猜。
     */
    public HrDataScopeOptionsVO options() {
        HrDataScopeOptionsVO vo = new HrDataScopeOptionsVO();
        List<IdNameOption> legalEntities = optionMapper.selectLegalEntities();
        List<IdNameOption> organizations = optionMapper.selectOrganizations();
        vo.setLegalEntities(legalEntities);
        vo.setOrganizations(organizations);
        vo.setOrganizationEmpty(organizations.isEmpty());
        return vo;
    }

    /**
     * 全量替换某角色的规则（页面语义是"保存这一版"，不是逐条增删）。
     *
     * @param roleId 角色
     * @param rules  新规则集合；传空表示"清空规则"——该角色的人将看不到任何业务数据
     */
    @Transactional(rollbackFor = Exception.class)
    public void save(Long roleId, List<HrDataScopeRuleDTO> rules) {
        if (roleId == null) {
            throw new HrDataScopeException("角色不能为空");
        }
        if (authLookupMapper.countRole(roleId) == 0) {
            throw new HrDataScopeException("角色不存在或已删除：" + roleId);
        }
        List<HrDataScopeRuleDTO> list = rules == null ? List.of() : rules;
        if (list.size() > MAX_RULES_PER_ROLE) {
            throw new HrDataScopeException("单个角色最多配置 " + MAX_RULES_PER_ROLE + " 条范围规则");
        }

        boolean hasAll = list.stream().anyMatch(r -> HrDataScopeType.ALL == HrDataScopeType.of(r.getScopeType()));
        if (hasAll && list.size() > 1) {
            throw new HrDataScopeException("「全量」已包含所有数据，不能再与其他范围同时配置");
        }

        // 先校验全部通过再落库，避免"删了旧的、新的没写进去"留下空档
        List<DataScopeRuleEntity> toInsert = new ArrayList<>(list.size());
        for (HrDataScopeRuleDTO dto : list) {
            toInsert.add(toEntity(roleId, dto));
        }

        ruleMapper.delete(new LambdaQueryWrapper<DataScopeRuleEntity>()
            .eq(DataScopeRuleEntity::getRoleId, roleId));
        for (DataScopeRuleEntity entity : toInsert) {
            entity.setId(null);
            ruleMapper.insert(entity);
        }

        evictRoleUsers(roleId);
        log.info("[数据权限] 保存规则：roleId={}, 条数={}, 操作人={}", roleId, toInsert.size(),
            currentUserName());
    }

    /**
     * 清理该角色下所有账号的登录上下文缓存。
     */
    public void evictRoleUsers(Long roleId) {
        List<Long> userIds = authLookupMapper.selectUserIdsByRoleId(roleId);
        for (Long userId : userIds) {
            contextLoader.evict(userId);
        }
        if (!userIds.isEmpty()) {
            log.info("[数据权限] 已清理 {} 个账号的上下文缓存：roleId={}", userIds.size(), roleId);
        }
    }

    private DataScopeRuleEntity toEntity(Long roleId, HrDataScopeRuleDTO dto) {
        HrDataScopeType type = HrDataScopeType.of(dto.getScopeType());
        if (type == null) {
            throw new HrDataScopeException("不支持的权限范围：" + dto.getScopeType());
        }
        DataScopeRuleEntity entity = new DataScopeRuleEntity();
        entity.setRoleId(roleId);
        entity.setScopeType(type.getCode());
        entity.setCanExport(Boolean.TRUE.equals(dto.getCanExport()));
        entity.setRemark(dto.getRemark());

        switch (type) {
            case ALL, SELF -> entity.setScopeValue(null);
            case COMPANY -> {
                Long id = requireId(dto.getScopeValue(), "本公司范围需要选择法人");
                if (authLookupMapper.countLegalEntity(id) == 0) {
                    throw new HrDataScopeException("法人不存在：" + id);
                }
                entity.setScopeValue(String.valueOf(id));
            }
            case ORG, ORG_TREE -> {
                Long id = requireId(dto.getScopeValue(), "组织范围需要选择组织");
                Organization org = organizationMapper.selectById(id);
                if (org == null) {
                    throw new HrDataScopeException("组织不存在：" + id);
                }
                entity.setScopeValue(String.valueOf(id));
            }
            default -> throw new HrDataScopeException("不支持的权限范围：" + type);
        }
        return entity;
    }

    private Long requireId(String raw, String message) {
        if (raw == null || raw.isBlank()) {
            throw new HrDataScopeException(message);
        }
        try {
            long id = Long.parseLong(raw.trim());
            if (id <= 0) {
                throw new NumberFormatException();
            }
            return id;
        } catch (NumberFormatException e) {
            throw new HrDataScopeException(message + "（当前值：" + raw + "）");
        }
    }

    /**
     * 把 scope_value 翻译成名称；查不到就原样显示 ID，让配置漏洞在页面上暴露出来。
     */
    private String resolveName(String scopeType, String scopeValue) {
        HrDataScopeType type = HrDataScopeType.of(scopeType);
        if (type == null || scopeValue == null || scopeValue.isBlank()) {
            return null;
        }
        Long id;
        try {
            id = Long.parseLong(scopeValue.trim());
        } catch (NumberFormatException e) {
            return "非法取值：" + scopeValue;
        }
        if (type == HrDataScopeType.COMPANY) {
            String name = authLookupMapper.selectLegalEntityName(id);
            return name == null ? "法人已不存在（ID " + id + "）" : name;
        }
        if (type == HrDataScopeType.ORG || type == HrDataScopeType.ORG_TREE) {
            Organization org = organizationMapper.selectById(id);
            return org == null ? "组织已不存在（ID " + id + "）" : org.getOrgName();
        }
        return null;
    }

    private String currentUserName() {
        try {
            return org.dromara.common.satoken.utils.LoginHelper.getUsername();
        } catch (Exception e) {
            return "system";
        }
    }
}
