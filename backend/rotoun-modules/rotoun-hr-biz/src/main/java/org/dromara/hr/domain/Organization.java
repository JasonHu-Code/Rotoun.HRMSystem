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
 * 组织节点（organization）。
 *
 * <p>本系统弃用底座的 {@code sys_dept}：底座部门只有父子两级语义，撑不住 13 个法人 × 6 级组织的实测结构。
 * {@code org_path}（形如 {@code /1/3/15/}）是数据权限 ORG_TREE 的匹配依据，也是唯一能一次查完整棵子树的手段。
 */
@Data
@TableName("organization")
public class Organization implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    @TableId(value = "id", type = IdType.AUTO)
    private Long id;

    /** 组织编码，全局唯一 */
    private String orgCode;

    private String orgName;

    /** 所属法人 */
    private Long legalEntityId;

    /** 上级组织；根节点为 0 */
    private Long parentId;

    /** 路径 /1/3/15/；写节点时必须维护 */
    private String orgPath;

    /** 层级 1-10 */
    private Integer orgLevel;

    /** GROUP / COMPANY / CENTER / DEPARTMENT / TEAM / LINE */
    private String orgType;

    /** 是否生产单元：决定是否启用倒班排班与计件 */
    private Boolean isProduction;

    private String costCenterCode;

    private Long leaderEmployeeId;

    /** ENABLED / DISABLED */
    private String status;

    private LocalDate effectiveDate;

    /** ISO 受控文件编号 */
    private String sourceDocNo;

    private String sourceDocVersion;

    private Integer sortNo;

    @TableLogic
    private Integer isDeleted;

    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private LocalDateTime createAt;

    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private LocalDateTime updateAt;
}
