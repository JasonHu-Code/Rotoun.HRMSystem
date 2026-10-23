package org.dromara.hr.domain.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.io.Serial;
import java.io.Serializable;
import java.util.List;

/**
 * 保存某角色数据权限的入参：整份提交，服务端全量替换。
 */
@Data
public class HrDataScopeRuleSaveDTO implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    @NotNull(message = "角色不能为空")
    private Long roleId;

    /** 传空数组表示清空该角色规则（该角色的人将看不到任何业务数据） */
    @Valid
    private List<HrDataScopeRuleDTO> rules;
}
