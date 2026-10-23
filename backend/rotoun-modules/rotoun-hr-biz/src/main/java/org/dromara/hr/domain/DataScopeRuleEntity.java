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
import java.time.LocalDateTime;

/**
 * 数据权限规则（data_scope_rule）——一个角色可以有多条，运行时取并集。
 *
 * <p>与 {@link org.dromara.hr.datascope.HrDataScopeRule} 的关系：本类是持久化实体，
 * 那个是运行期模型（多一个 {@code pathPrefix}，由装配层从 {@code organization.org_path} 解析出来）。
 * 不做成一个类是故意的——运行期模型要能脱离 Spring、脱离数据库单独单测。
 */
@Data
@TableName("data_scope_rule")
public class DataScopeRuleEntity implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    @TableId(value = "id", type = IdType.AUTO)
    private Long id;

    private Long roleId;

    /** ALL / COMPANY / ORG_TREE / ORG / SELF */
    private String scopeType;

    /** COMPANY=法人ID；ORG_TREE/ORG=组织ID；ALL/SELF 为空 */
    private String scopeValue;

    /** 0 不可导出 1 可导出 */
    private Boolean canExport;

    private String remark;

    @TableLogic
    private Integer isDeleted;

    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private LocalDateTime createAt;

    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private LocalDateTime updateAt;
}
