package org.dromara.hr.datascope;

import org.apache.ibatis.mapping.BoundSql;
import org.apache.ibatis.mapping.MappedStatement;
import org.apache.ibatis.session.Configuration;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 数据权限拦截器：验证最终拼出来的 SQL。
 *
 * <p>这里不连数据库，只验证三件事：条件有没有拼进去、拼在哪个别名上、别名写错会不会 fail-fast。
 * 对应《M0 底座改造清单》3.9 的第 10 条（分页/总数是 SQL 层过滤）与第 12 条（未标注的方法不被注入）。
 */
class HrDataPermissionInterceptorTest {

    /** 用于反射取注解的假 Mapper；真实项目里注解写在业务 Mapper 的方法上 */
    interface FakeEmployeeMapper {
        @HrDataScope(orgAlias = "em", empAlias = "e")
        List<Object> selectWithScope();

        List<Object> selectWithoutScope();
    }

    private static final String MS_ID_SCOPED =
        "org.dromara.hr.datascope.HrDataPermissionInterceptorTest$FakeEmployeeMapper.selectWithScope";
    private static final String MS_ID_PLAIN =
        "org.dromara.hr.datascope.HrDataPermissionInterceptorTest$FakeEmployeeMapper.selectWithoutScope";

    private static final String SQL =
        "SELECT e.id, e.name FROM employee e LEFT JOIN employment em ON em.employee_id = e.id AND em.is_current = 1 WHERE e.is_deleted = 0";

    private final HrDataPermissionInterceptor interceptor = new HrDataPermissionInterceptor();

    @Test
    void should_append_condition_on_declared_alias() throws Exception {
        HrDataScopeRule rule = new HrDataScopeRule(10L, "COMPANY", "3");
        String sql = apply(SQL, ctx(rule), MS_ID_SCOPED);

        assertTrue(sql.contains("em.legal_entity_id IN (3)"), "条件应拼在注解声明的别名 em 上，实际：" + sql);
        assertTrue(sql.contains("e.is_deleted = 0"), "原有业务条件要保留，实际：" + sql);
    }

    @Test
    void should_deny_when_no_rule() throws Exception {
        String sql = apply(SQL, ctx(), MS_ID_SCOPED);
        assertTrue(sql.contains("1 = 0"), "没有规则必须拒绝，实际：" + sql);
    }

    @Test
    void should_skip_all() throws Exception {
        String sql = apply(SQL, ctx(new HrDataScopeRule(1L, "ALL", null)), MS_ID_SCOPED);
        assertEquals(SQL, sql, "ALL 不应改动 SQL");
    }

    @Test
    void should_not_touch_method_without_annotation() throws Exception {
        String sql = apply(SQL, ctx(new HrDataScopeRule(10L, "COMPANY", "3")), MS_ID_PLAIN);
        assertEquals(SQL, sql, "未标注 @HrDataScope 的方法不应被注入");
    }

    @Test
    void should_fail_fast_when_alias_missing() {
        // 别名写错：宁可这次查询报错，也不能让条件静默消失变成全量放行
        assertThrows(HrDataScopeException.class,
            () -> apply("SELECT e.id FROM employee e WHERE e.is_deleted = 0",
                ctx(new HrDataScopeRule(10L, "COMPANY", "3")), MS_ID_SCOPED));
    }

    @Test
    void should_filter_count_query_as_well() throws Exception {
        // 分页 count：条件必须进到 count 里，否则总数与列表不一致
        String countSql = "SELECT COUNT(*) FROM employee e LEFT JOIN employment em ON em.employee_id = e.id WHERE e.is_deleted = 0";
        String sql = apply(countSql, ctx(new HrDataScopeRule(11L, "ORG", "15")), MS_ID_SCOPED);
        assertTrue(sql.contains("em.organization_id IN (15)"), "count 也要被过滤，实际：" + sql);
        assertFalse(sql.contains("1 = 0"));
    }

    private String apply(String sql, HrLoginContext ctx, String msId) throws Exception {
        MappedStatement ms = mock(MappedStatement.class);
        when(ms.getId()).thenReturn(msId);
        BoundSql boundSql = new BoundSql(new Configuration(), sql, new ArrayList<>(), null);
        HrContextHolder.set(ctx);
        try {
            interceptor.beforeQuery(null, ms, null, null, null, boundSql);
        } finally {
            HrContextHolder.clear();
        }
        return boundSql.getSql();
    }

    private HrLoginContext ctx(HrDataScopeRule... rules) {
        HrLoginContext ctx = new HrLoginContext();
        ctx.setUserId(1L);
        ctx.setEmployeeId(1001L);
        ctx.setScopeRules(List.of(rules));
        return ctx;
    }
}
