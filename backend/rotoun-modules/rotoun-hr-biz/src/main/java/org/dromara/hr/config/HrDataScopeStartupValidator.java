package org.dromara.hr.config;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/**
 * 启动自检：数据权限的"静默失效"比报错更危险，启动时把可疑配置一次性摊开。
 *
 * <p>检查四类问题，全部只告警不阻断启动——开发环境库可能还没建表，
 * 直接 fail-fast 会让"还没导入数据"变成"服务起不来"：
 * <ol>
 *     <li>角色还在用底座的 {@code sys_role.data_scope} 却没迁到 {@code data_scope_rule}：该角色的人会看不到任何数据；</li>
 *     <li>规则里的组织 ID 在 {@code organization} 中不存在（组织被删/尚未导入）：ORG/ORG_TREE 规则整条失效；</li>
 *     <li>在职员工没绑登录账号、或一个账号绑了多个员工：前者登不上，后者权限装配到"随机一个人"；</li>
 *     <li>{@code employee.sys_user_id} 唯一索引缺失：上面那条重复绑定迟早发生。</li>
 * </ol>
 */
@Slf4j
@Component
@Order
@RequiredArgsConstructor
public class HrDataScopeStartupValidator implements ApplicationRunner {

    private static final String LOG_TAG = "[HR数据权限自检]";

    private final JdbcTemplate jdbcTemplate;

    @Override
    public void run(ApplicationArguments args) {
        try {
            checkRoleMigration();
            checkAssignedRoleWithoutRule();
            checkRuleOrgExists();
            checkEmployeeAccountBinding();
            checkUniqueIndex();
            log.info("{} 完成", LOG_TAG);
        } catch (Exception e) {
            // 库还没建、脚本还没跑时这里必然失败，属正常情况，不打断启动
            log.warn("{} 跳过（数据库不可用或表结构未就绪）：{}", LOG_TAG, e.getMessage());
        }
    }

    /**
     * 底座 data_scope 还在生效、但没有对应规则的角色。
     */
    private void checkRoleMigration() {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList("""
            SELECT r.role_id, r.role_name, r.data_scope
            FROM sys_role r
            WHERE r.del_flag = '0'
              AND r.status = '0'
              AND r.role_key <> 'superadmin'
              AND IFNULL(r.data_scope, '0') NOT IN ('0')
              AND NOT EXISTS (
                    SELECT 1 FROM data_scope_rule d
                    WHERE d.role_id = r.role_id AND d.is_deleted = 0
              )
            """);
        if (!rows.isEmpty()) {
            log.warn("{} {} 个角色还没有生效的 data_scope_rule，这些角色的人将看不到任何业务数据。" +
                "原因可能是：① 未执行 db/07_m0_datascope.sql；② 脚本里的 @legal_entity_id / @org_id 还没填：",
                LOG_TAG, rows.size());
            rows.forEach(r -> log.warn("{}   roleId={}, roleName={}, data_scope={}",
                LOG_TAG, r.get("role_id"), r.get("role_name"), r.get("data_scope")));
        }
    }

    /**
     * 已经分配了人、却没有生效规则的角色。
     *
     * <p>这类问题不会报错，只会让这批人登录后"什么都看不到"，最难排查。
     * 典型来源：配了 hr_company 角色但 07 脚本里的 @legal_entity_id 忘了填。
     */
    private void checkAssignedRoleWithoutRule() {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList("""
            SELECT r.role_id, r.role_name, COUNT(DISTINCT ur.user_id) AS user_cnt
            FROM sys_role r
            JOIN sys_user_role ur ON ur.role_id = r.role_id
            WHERE r.del_flag = '0' AND r.status = '0'
              AND r.role_key <> 'superadmin'
              AND NOT EXISTS (
                    SELECT 1 FROM data_scope_rule d
                    WHERE d.role_id = r.role_id AND d.is_deleted = 0
              )
            GROUP BY r.role_id, r.role_name
            """);
        if (!rows.isEmpty()) {
            log.warn("{} {} 个角色已分配用户但没有任何生效规则，这些用户登录后将看不到业务数据：",
                LOG_TAG, rows.size());
            rows.forEach(r -> log.warn("{}   roleId={}, roleName={}, 用户数={}",
                LOG_TAG, r.get("role_id"), r.get("role_name"), r.get("user_cnt")));
        }
    }

    /**
     * ORG / ORG_TREE 规则指向的组织是否存在。
     */
    private void checkRuleOrgExists() {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList("""
            SELECT d.id, d.role_id, d.scope_type, d.scope_value
            FROM data_scope_rule d
            LEFT JOIN organization o ON o.id = d.scope_value AND o.is_deleted = 0
            WHERE d.is_deleted = 0
              AND d.scope_type IN ('ORG', 'ORG_TREE')
              AND o.id IS NULL
            """);
        if (!rows.isEmpty()) {
            log.warn("{} {} 条组织类规则指向的组织不存在，规则不会生效：", LOG_TAG, rows.size());
            rows.forEach(r -> log.warn("{}   ruleId={}, roleId={}, type={}, scopeValue={}",
                LOG_TAG, r.get("id"), r.get("role_id"), r.get("scope_type"), r.get("scope_value")));
        }
    }

    /**
     * 员工与账号的绑定完整性。
     */
    private void checkEmployeeAccountBinding() {
        Integer unbound = jdbcTemplate.queryForObject("""
            SELECT COUNT(*) FROM employee
            WHERE is_deleted = 0
              AND sys_user_id IS NULL
              AND employee_status IN ('PROBATION', 'ACTIVE', 'REHIRED')
            """, Integer.class);
        if (unbound != null && unbound > 0) {
            log.warn("{} {} 名在职员工未绑定登录账号（sys_user_id 为空），这些员工无法登录自助端", LOG_TAG, unbound);
        }

        List<Map<String, Object>> dup = jdbcTemplate.queryForList("""
            SELECT sys_user_id, COUNT(*) AS cnt
            FROM employee
            WHERE sys_user_id IS NOT NULL AND is_deleted = 0
            GROUP BY sys_user_id HAVING COUNT(*) > 1
            """);
        if (!dup.isEmpty()) {
            log.error("{} 一个账号绑定了多个员工，权限装配结果不确定：{}", LOG_TAG, dup);
        }
    }

    /**
     * 唯一索引是否已建（07 脚本的第一段）。
     */
    private void checkUniqueIndex() {
        Integer exists = jdbcTemplate.queryForObject("""
            SELECT COUNT(*) FROM information_schema.statistics
            WHERE table_schema = DATABASE()
              AND table_name = 'employee'
              AND index_name = 'uk_employee_sys_user_id'
            """, Integer.class);
        if (exists == null || exists == 0) {
            log.warn("{} employee.sys_user_id 缺少唯一索引 uk_employee_sys_user_id，请执行 db/07_m0_datascope.sql", LOG_TAG);
        }
    }
}
