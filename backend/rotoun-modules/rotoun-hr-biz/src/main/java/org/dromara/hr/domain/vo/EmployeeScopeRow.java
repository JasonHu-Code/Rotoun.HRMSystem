package org.dromara.hr.domain.vo;

import lombok.Data;

import java.io.Serial;
import java.io.Serializable;

/**
 * 员工列表投影（数据权限验证与后续列表页共用的最小字段集）。
 *
 * <p>为什么不直接返回 {@code Employee}：列表页只需要"人 + 归属"，把身份证、住址这些敏感列
 * 带进 SQL 没有收益，反而扩大脱敏疏漏的面。这里显式列出需要的列，SQL 也跟着只查这些。
 */
@Data
public class EmployeeScopeRow implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    private Long id;

    private String empNo;

    private String empName;

    /** 主岗组织 */
    private Long organizationId;

    /** 主岗用工主体 */
    private Long legalEntityId;
}
