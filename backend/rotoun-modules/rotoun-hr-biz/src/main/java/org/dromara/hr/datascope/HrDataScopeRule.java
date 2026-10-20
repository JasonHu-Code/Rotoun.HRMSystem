package org.dromara.hr.datascope;

import lombok.Data;

import java.io.Serializable;

/**
 * 数据权限规则（对应 {@code data_scope_rule} 表的一行，按角色配置）。
 *
 * <p>{@link #pathPrefix} 不是表字段：装配登录上下文时把 ORG_TREE 的 {@code scope_value}
 * （组织 ID）解析成 {@code org_path} 前缀（形如 {@code /1/3/}），避免每次拼 SQL 都回查组织表，
 * 也让 SQL 生成保持纯逻辑、可单测。
 */
@Data
public class HrDataScopeRule implements Serializable {

    private Long id;

    /** 角色 ID（sys_role.role_id） */
    private Long roleId;

    /** 范围类型，见 {@link HrDataScopeType} */
    private String scopeType;

    /** 范围取值：COMPANY=法人ID，ORG_TREE/ORG=组织ID，ALL/SELF 为空 */
    private String scopeValue;

    /** 是否可导出：0 不可导出 1 可导出 */
    private Boolean canExport;

    /** ORG_TREE 解析后的路径前缀，形如 /1/3/ ；非 ORG_TREE 类型为空 */
    private String pathPrefix;

    public HrDataScopeRule() {
    }

    public HrDataScopeRule(Long roleId, String scopeType, String scopeValue) {
        this.roleId = roleId;
        this.scopeType = scopeType;
        this.scopeValue = scopeValue;
    }

    public boolean isAll() {
        return HrDataScopeType.ALL.getCode().equalsIgnoreCase(scopeType);
    }
}
