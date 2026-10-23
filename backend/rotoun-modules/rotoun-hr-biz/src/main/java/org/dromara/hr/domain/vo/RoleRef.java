package org.dromara.hr.domain.vo;

import lombok.Data;

import java.io.Serial;
import java.io.Serializable;

/**
 * 角色引用（只取数据权限装配需要的两列，不引入 rotoun-system 模块依赖）。
 */
@Data
public class RoleRef implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    private Long roleId;

    /** 角色权限字符串，仅用于日志与告警定位 */
    private String roleKey;
}
