package org.dromara.hr.domain;

import com.baomidou.mybatisplus.annotation.FieldStrategy;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableLogic;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.io.Serial;
import java.io.Serializable;
import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * 任职记录（employment）。
 *
 * <p>员工与组织的关系是"多段历史"而不是"一个字段"：调岗不覆盖上一条，而是关掉 is_current 再插一条。
 * 数据权限与历史报表都靠这个结构——原主管查历史考勤时，必须能按当时的 organization_id 看到人
 * （M0 验收用例 11）。同理 {@link #legalEntityId} 是"用工主体"，可以与组织所属法人不同，
 * 用来表达跨法人派驻，这也是实测里 73 人工号公司与职位组织不符的那批数据要落的地方。
 */
@Data
@TableName("employment")
public class Employment implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    @TableId(value = "id", type = IdType.AUTO)
    private Long id;

    private Long employeeId;

    private Long positionId;

    /** 所在组织（冗余，便于直接过滤，不必回查 position） */
    private Long organizationId;

    /** 用工主体（工号所属法人），可与组织所属法人不同 */
    private Long legalEntityId;

    /** PRIMARY 主岗 / CONCURRENT 兼岗 */
    private String employmentType;

    private LocalDate startDate;

    /** 在职为 9999-12-31 */
    private LocalDate endDate;

    /** HIRE / REGULAR / TRANSFER / PROMOTE / SALARY_ADJUST / DISPATCH / RESIGN / REHIRE */
    private String changeType;

    private String changeOrderNo;

    /** 当前记录 1 / 历史 0 */
    private Boolean isCurrent;

    @TableLogic
    private Integer isDeleted;

    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private LocalDateTime createAt;

    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private LocalDateTime updateAt;
}
