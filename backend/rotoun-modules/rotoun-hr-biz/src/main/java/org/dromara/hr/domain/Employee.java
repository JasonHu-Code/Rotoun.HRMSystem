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
 * 员工主数据（employee）。
 *
 * <p>为什么不继承底座 {@code BaseEntity}：底座基类带 create_by / update_by / create_time 等列，
 * 而本系统的业务表统一用 {@code create_at / update_at} 且没有操作人列（审计另走 biz_change_log）。
 * 硬套基类会让 insert 去写不存在的列，也会被底座的自动填充逻辑覆盖。
 *
 * <p>时间列交给数据库默认值（{@code DEFAULT CURRENT_TIMESTAMP(3)}），
 * 实体上标 {@link FieldStrategy#NEVER}，避免 MP 把 null 写进去。
 *
 * <p>身份证/手机号只出现密文与脱敏列：明文永不出库，Service 层负责加解密。
 */
@Data
@TableName("employee")
public class Employee implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    /** 主键 */
    @TableId(value = "id", type = IdType.AUTO)
    private Long id;

    /** 工号，{公司码2}{入司年2}{序号6}，不可变 */
    private String empNo;

    /** 姓名 */
    private String empName;

    /** 曾用名 */
    private String usedName;

    /** 身份证号密文（AES-256-GCM） */
    private String idCardCipher;

    /** 身份证号 SHA-256，用于唯一性校验 */
    private String idCardHash;

    /** 身份证号脱敏展示值 */
    private String idCardMask;

    /** 性别：MALE / FEMALE */
    private String gender;

    private LocalDate birthday;

    private String nationCode;

    private String nativePlaceCode;

    private String nationalityCode;

    private String politicalStatus;

    private String maritalStatus;

    private String healthStatus;

    private String mobileCipher;

    private String mobileMask;

    private String address;

    private String householdAddress;

    private String householdType;

    private String emergencyContact;

    private String emergencyMobileCipher;

    private String educationLevel;

    private String degree;

    private String title;

    private String workAreaCode;

    /** 参加工作日期（社会工龄，年假依据） */
    private LocalDate firstWorkDate;

    /** 入职日期（司龄） */
    private LocalDate entryDate;

    /** PENDING / PROBATION / ACTIVE / SUSPENDED / RESIGNING / RESIGNED / REHIRED */
    private String employeeStatus;

    /** CONTRACT / LABOR / REHIRE / INTERN */
    private String employmentNature;

    /** FORMAL / INTERN / DISPATCH / EXPATRIATE / OTHER */
    private String employeeCategory;

    /** 当前主任职记录 ID，便于免 join 查询 */
    private Long currentEmploymentId;

    /** 关联登录账号 sys_user.user_id；唯一，允许为 null（未建账号） */
    private Long sysUserId;

    private String avatarPath;

    private String remark;

    @TableLogic
    private Integer isDeleted;

    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private LocalDateTime createAt;

    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private LocalDateTime updateAt;
}
