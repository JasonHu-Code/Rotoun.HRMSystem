package org.dromara.hr.domain.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.io.Serial;
import java.io.Serializable;

/**
 * 数据权限规则编辑入参。
 *
 * <p>为什么单独建 DTO 而不是直接收实体：{@code scope_value} 的合法性依赖 {@code scope_type}
 * （COMPANY 要法人 ID、ORG/ORG_TREE 要组织 ID、ALL/SELF 必须为空），这层校验放在 DTO + Service 里，
 * 实体只负责落库。
 */
@Data
public class HrDataScopeRuleDTO implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    /** 更新时传，新增留空 */
    private Long id;

    /** ALL / COMPANY / ORG_TREE / ORG / SELF */
    @NotBlank(message = "权限范围不能为空")
    private String scopeType;

    /** 法人 ID 或组织 ID；ALL/SELF 留空 */
    private String scopeValue;

    /** 是否允许导出 */
    private Boolean canExport;

    @Size(max = 200, message = "备注不能超过 200 字")
    private String remark;
}
