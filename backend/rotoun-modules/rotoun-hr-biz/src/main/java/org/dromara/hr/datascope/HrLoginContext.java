package org.dromara.hr.datascope;

import lombok.Data;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/**
 * HR 登录上下文：一次登录后装配，缓存在 Redis（{@code hr:login:{userId}}），请求内放 ThreadLocal。
 *
 * <p>为什么单独建这个类而不改底座的 {@code LoginUser}：底座 {@code LoginUser} 在
 * {@code rotoun-common-satoken} 里，改它会影响所有模块；且底座只认 dept，不认 organization。
 * 这里按 M0 清单 2.5 的绑定链路（employee.sys_user_id → employment 主岗 → organization）单独装配。
 *
 * <p>纯管理员（无员工档案）时 {@link #employeeId} 为 null：允许登录，但 SELF 规则解析成
 * "查不到任何数据"，并在装配时告警——不允许退化成全量。
 */
@Data
public class HrLoginContext implements Serializable {

    /** 登录账号 ID（sys_user.user_id） */
    private Long userId;

    /** 员工 ID；纯管理员为 null */
    private Long employeeId;

    /** 主岗组织 ID */
    private Long organizationId;

    /** 主岗所属法人 ID */
    private Long legalEntityId;

    /** 主岗组织路径，形如 /1/3/15/ */
    private String orgPath;

    /** 主岗职位 ID */
    private Long positionId;

    /** 角色编码集合，便于日志与告警定位 */
    private Set<String> roleCodes;

    /** 数据权限规则；为空表示"看不到任何业务数据" */
    private List<HrDataScopeRule> scopeRules = new ArrayList<>();

    /** 是否可导出：任一规则 can_export=1 */
    private boolean canExport;
}
