package org.dromara.hr.datascope;

import java.lang.annotation.*;

/**
 * HR 业务数据权限注解。<br>
 * 标注在 Mapper 方法（或 Mapper 接口）上，由 {@link HrDataPermissionInterceptor} 在 SQL 执行前
 * 追加组织维度的数据范围条件。
 *
 * <p>为什么不用底座的 {@code @DataPermission}：底座那套读 {@code sys_role.data_scope} 且按
 * {@code sys_dept} 过滤，而本系统弃用 {@code sys_dept}、改用自建 {@code organization}，
 * 两套口径不能混用。这里另起一个注解名，彻底避免与底座同名类/注解冲突，
 * 也让"哪些 SQL 受组织权限约束"这件事在代码里一眼可见。
 *
 * <p>别名必填（不给默认值兜底）：SQL 一旦写多表 join，默认值会在错误的别名上拼条件，
 * 静默变成"少过滤"甚至"全量放行"，属于越权事故。宁可编码时多写两个字符。
 */
@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface HrDataScope {

    /**
     * 组织列（{@code organization_id}）所在表的别名，必填，如 {@code "em"}。
     */
    String orgAlias();

    /**
     * 员工列（{@code employee_id}）所在表的别名，必填，如 {@code "e"}。
     */
    String empAlias();

    /**
     * 法人列（{@code legal_entity_id}）所在表的别名；留空表示与 {@link #orgAlias()} 同表。
     */
    String legalAlias() default "";

    /**
     * 组织列名，默认 {@code organization_id}。
     */
    String orgColumn() default "organization_id";

    /**
     * 法人列名，默认 {@code legal_entity_id}。
     */
    String legalColumn() default "legal_entity_id";

    /**
     * 员工列名，默认 {@code employee_id}；查 employee 主表时应显式写 {@code "id"}。
     */
    String empColumn() default "employee_id";

    /**
     * 组织路径列名，默认 {@code org_path}；ORG_TREE 前缀匹配用。
     */
    String orgPathColumn() default "org_path";
}
