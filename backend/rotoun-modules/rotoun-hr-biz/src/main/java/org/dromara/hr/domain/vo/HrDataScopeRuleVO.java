package org.dromara.hr.domain.vo;

import lombok.Data;

import java.io.Serial;
import java.io.Serializable;

/**
 * 数据权限规则展示对象。
 *
 * <p>比实体多一个 {@link #scopeName}：前端不该看到裸 ID（"组织 15"谁也认不出），
 * 但又不能只在编辑时解析——列表态也需要显示名称。名称在 Service 层批量查出来，避免逐行回表。
 */
@Data
public class HrDataScopeRuleVO implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    private Long id;

    private Long roleId;

    private String scopeType;

    private String scopeValue;

    /** 法人名称 / 组织名称；ALL、SELF 为空 */
    private String scopeName;

    private Boolean canExport;

    private String remark;
}
