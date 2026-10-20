package org.dromara.hr.datascope;

import org.junit.jupiter.api.Test;

import java.lang.annotation.Annotation;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * 数据权限规则 → SQL 条件片段。
 *
 * <p>对应《M0 底座改造清单》3.9 的 12 条验收用例中的 1–7、12（条件生成层，不连数据库）。
 * 这些用例是"默认拒绝 / ALL 优先 / 多角色并集"三条硬规则的守门测试，改动 Builder 必须全绿。
 */
class HrDataScopeSqlBuilderTest {

    private final HrDataScopeSqlBuilder builder = new HrDataScopeSqlBuilder();

    /** 典型用法：employee e join employment em，组织列在 em 上，员工列在 e 上 */
    private final HrDataScope ann = ann("em", "e");

    @Test
    void all_should_not_append_any_condition() {
        HrLoginContext ctx = ctx(rule(1L, "ALL", null));
        assertNull(builder.build(ann, ctx), "ALL 不应追加条件，否则 OR 上 1=0 会把全量又收窄");
    }

    @Test
    void company_should_filter_by_legal_entity() {
        HrLoginContext ctx = ctx(rule(10L, "COMPANY", "3"));
        assertEquals("em.legal_entity_id IN (3)", builder.build(ann, ctx));
    }

    @Test
    void org_tree_should_filter_by_path_prefix() {
        HrDataScopeRule rule = rule(11L, "ORG_TREE", "15");
        rule.setPathPrefix("/1/3/15/");
        HrLoginContext ctx = ctx(rule);
        assertEquals("em.org_path LIKE '/1/3/15/%'", builder.build(ann, ctx));
    }

    @Test
    void org_should_filter_exact_organization() {
        HrLoginContext ctx = ctx(rule(12L, "ORG", "15"));
        assertEquals("em.organization_id IN (15)", builder.build(ann, ctx));
    }

    @Test
    void self_should_filter_by_employee_id() {
        HrLoginContext ctx = ctx(rule(13L, "SELF", null));
        ctx.setEmployeeId(1001L);
        assertEquals("e.employee_id = 1001", builder.build(ann, ctx));
    }

    @Test
    void multi_role_should_union_conditions() {
        HrDataScopeRule tree = rule(11L, "ORG_TREE", "15");
        tree.setPathPrefix("/1/3/15/");
        HrLoginContext ctx = ctx(rule(10L, "COMPANY", "3"), tree);
        ctx.setEmployeeId(1001L);

        String condition = builder.build(ann, ctx);

        assertEquals("em.legal_entity_id IN (3) OR em.org_path LIKE '/1/3/15/%'", condition);
    }

    @Test
    void no_rule_should_deny() {
        assertEquals(HrDataScopeSqlBuilder.DENY, builder.build(ann, ctx()));
        assertEquals(HrDataScopeSqlBuilder.DENY, builder.build(ann, null), "未登录同样拒绝，不能放行");
    }

    @Test
    void self_without_employee_should_deny() {
        // 纯管理员没有员工档案：SELF 无意义，必须退化成拒绝而不是全量
        HrLoginContext ctx = ctx(rule(13L, "SELF", null));
        ctx.setEmployeeId(null);
        assertEquals(HrDataScopeSqlBuilder.DENY, builder.build(ann, ctx));
    }

    @Test
    void unknown_scope_type_should_be_ignored() {
        HrLoginContext ctx = ctx(rule(14L, "CUSTOM", "9"), rule(10L, "COMPANY", "3"));
        assertEquals("em.legal_entity_id IN (3)", builder.build(ann, ctx),
            "无法识别的类型要跳过且不报错，但不能因此放宽其它规则");
    }

    @Test
    void illegal_scope_value_should_throw() {
        HrLoginContext ctx = ctx(rule(10L, "COMPANY", "3) OR 1=1 --"));
        assertThrows(HrDataScopeException.class, () -> builder.build(ann, ctx),
            "scope_value 是拼进 SQL 的裸值，非数字必须直接失败");
    }

    @Test
    void legal_alias_fallback_to_org_alias() {
        HrLoginContext ctx = ctx(rule(10L, "COMPANY", "3"), rule(20L, "COMPANY", "5"));
        assertEquals("em.legal_entity_id IN (3, 5)", builder.build(ann, ctx), "同类型多值合并为 IN");
    }

    private HrLoginContext ctx(HrDataScopeRule... rules) {
        HrLoginContext ctx = new HrLoginContext();
        ctx.setUserId(1L);
        ctx.setScopeRules(Arrays.asList(rules));
        return ctx;
    }

    private HrDataScopeRule rule(Long roleId, String scopeType, String scopeValue) {
        return new HrDataScopeRule(roleId, scopeType, scopeValue);
    }

    /**
     * 注解是接口，测试里用匿名实现构造（等价于在 Mapper 方法上写 @HrDataScope(orgAlias="em", empAlias="e")）。
     */
    private HrDataScope ann(String orgAlias, String empAlias) {
        return new HrDataScope() {
            @Override
            public Class<? extends Annotation> annotationType() {
                return HrDataScope.class;
            }

            @Override
            public String orgAlias() {
                return orgAlias;
            }

            @Override
            public String empAlias() {
                return empAlias;
            }

            @Override
            public String legalAlias() {
                return "";
            }

            @Override
            public String orgColumn() {
                return "organization_id";
            }

            @Override
            public String legalColumn() {
                return "legal_entity_id";
            }

            @Override
            public String empColumn() {
                return "employee_id";
            }

            @Override
            public String orgPathColumn() {
                return "org_path";
            }
        };
    }

    @Test
    void same_type_values_should_merge_into_in() {
        HrLoginContext ctx = ctx(rule(10L, "ORG", "15"), rule(11L, "ORG", "16"));
        assertEquals("em.organization_id IN (15, 16)", builder.build(ann, ctx));
    }

    @Test
    void empty_rule_list_should_deny() {
        HrLoginContext ctx = new HrLoginContext();
        ctx.setScopeRules(List.of());
        assertEquals(HrDataScopeSqlBuilder.DENY, builder.build(ann, ctx));
    }
}
