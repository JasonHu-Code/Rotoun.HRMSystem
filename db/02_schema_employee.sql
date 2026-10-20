-- =====================================================================
-- HR 人事管理系统 · 建表脚本 02：员工、单据与合同
-- 数据库：rt-hrms    MySQL 8.0+    utf8mb4 / utf8mb4_general_ci
-- 依据：HR系统_数据库设计_V0.1.md 第五、六、七章
-- 表数：14
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- 1. employee 员工主数据
-- 一个自然人一份档案。工号不可变，调动不改。
-- 身份证/手机/银行卡采用「密文 + SHA256哈希 + 脱敏值」三件套：
--   密文带随机IV，无法建唯一索引 -> 靠 hash 去重
--   列表展示只用 mask，禁止查密文字段
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employee` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `emp_no` varchar(20) NOT NULL COMMENT '工号，规则 {公司码2位}{入司年2位}{序号6位}，不可变',
  `emp_name` varchar(50) NOT NULL COMMENT '姓名',
  `used_name` varchar(50) DEFAULT NULL COMMENT '曾用名',
  `id_card_cipher` varchar(200) DEFAULT NULL COMMENT '身份证号密文（AES-256-GCM）',
  `id_card_hash` varchar(64) DEFAULT NULL COMMENT '身份证号SHA-256，用于唯一性校验',
  `id_card_mask` varchar(30) DEFAULT NULL COMMENT '身份证号脱敏展示值，如 513***273X',
  `gender` varchar(10) DEFAULT NULL COMMENT '性别：MALE男 FEMALE女',
  `birthday` date DEFAULT NULL COMMENT '出生日期，可由身份证解析',
  `nation_code` varchar(10) DEFAULT NULL COMMENT '民族编码，关联字典',
  `native_place_code` varchar(20) DEFAULT NULL COMMENT '籍贯编码',
  `nationality_code` varchar(10) DEFAULT '01' COMMENT '国籍编码，默认01中国',
  `political_status` varchar(20) DEFAULT NULL COMMENT '政治面貌编码',
  `marital_status` varchar(20) DEFAULT NULL COMMENT '婚姻状况：MARRIED已婚 SINGLE未婚 WIDOWED丧偶 DIVORCED离异',
  `health_status` varchar(20) DEFAULT NULL COMMENT '健康状况：GOOD良好 NORMAL一般 DISABLED残疾',
  `mobile_cipher` varchar(200) DEFAULT NULL COMMENT '手机号密文',
  `mobile_mask` varchar(20) DEFAULT NULL COMMENT '手机号脱敏值',
  `address` varchar(200) DEFAULT NULL COMMENT '现住址',
  `household_address` varchar(200) DEFAULT NULL COMMENT '户口所在地',
  `household_type` varchar(20) DEFAULT NULL COMMENT '户口类型：RURAL_FAMILY农村家庭户 URBAN_FAMILY城镇家庭户 RURAL_COLLECTIVE农村集体户 URBAN_COLLECTIVE城镇集体户',
  `emergency_contact` varchar(50) DEFAULT NULL COMMENT '紧急联系人',
  `emergency_mobile_cipher` varchar(200) DEFAULT NULL COMMENT '紧急联系人电话密文',
  `education_level` varchar(20) DEFAULT NULL COMMENT '最高学历：PRIMARY小学 JUNIOR初中 HIGH高中 SECONDARY中专 COLLEGE大专 BACHELOR本科 MASTER硕士 DOCTOR博士',
  `degree` varchar(20) DEFAULT NULL COMMENT '学位：NONE无 BACHELOR学士 MASTER硕士 DOCTOR博士',
  `title` varchar(30) DEFAULT NULL COMMENT '职称，字典值',
  `work_area_code` varchar(20) DEFAULT NULL COMMENT '工作地区编码',
  `first_work_date` date DEFAULT NULL COMMENT '参加工作日期，用于算社会工龄（年假天数依据）',
  `entry_date` date NOT NULL COMMENT '入职日期，用于算司龄',
  `employee_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '员工状态：PENDING待入职 PROBATION试用 ACTIVE在职 SUSPENDED停薪留职 RESIGNING待离职 RESIGNED已离职 REHIRED返聘',
  `employment_nature` varchar(20) NOT NULL DEFAULT 'CONTRACT' COMMENT '用工性质：CONTRACT合同工 LABOR劳务工 REHIRE退休返聘 INTERN实习生',
  `employee_category` varchar(20) DEFAULT NULL COMMENT '员工类别：FORMAL正式 INTERN实习 DISPATCH服务派遣 EXPATRIATE外派 OTHER其他',
  `current_employment_id` bigint unsigned DEFAULT NULL COMMENT '当前主任职记录ID，便于免join查询',
  `sys_user_id` bigint unsigned DEFAULT NULL COMMENT '关联登录账号 sys_user.user_id',
  `avatar_path` varchar(300) DEFAULT NULL COMMENT '照片路径（不存二进制）',
  `remark` varchar(500) DEFAULT NULL COMMENT '备注',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_employee_emp_no` (`emp_no`),
  UNIQUE KEY `uk_employee_id_card_hash` (`id_card_hash`),
  KEY `idx_employee_emp_name` (`emp_name`),
  KEY `idx_employee_employee_status` (`employee_status`),
  KEY `idx_employee_current_employment_id` (`current_employment_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='员工主数据';


-- ---------------------------------------------------------------------
-- 2. employee_education 教育经历
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employee_education` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `school_name` varchar(100) NOT NULL COMMENT '学校名称',
  `major` varchar(100) DEFAULT NULL COMMENT '所学专业',
  `education_level` varchar(20) DEFAULT NULL COMMENT '学历，枚举同 employee.education_level',
  `degree` varchar(20) DEFAULT NULL COMMENT '学位，枚举同 employee.degree',
  `start_date` date DEFAULT NULL COMMENT '入学日期',
  `end_date` date DEFAULT NULL COMMENT '毕业日期',
  `is_highest` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否最高学历：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_employee_education_employee_id` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='教育经历';


-- ---------------------------------------------------------------------
-- 3. employee_work_experience 工作经历（入职前）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employee_work_experience` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `company_name` varchar(100) NOT NULL COMMENT '单位名称',
  `position_name` varchar(50) DEFAULT NULL COMMENT '担任职位',
  `start_date` date DEFAULT NULL COMMENT '开始日期',
  `end_date` date DEFAULT NULL COMMENT '结束日期',
  `leave_reason` varchar(200) DEFAULT NULL COMMENT '离职原因',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_employee_work_experience_employee_id` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='工作经历';


-- ---------------------------------------------------------------------
-- 4. employee_family 家庭成员
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employee_family` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `member_name` varchar(50) NOT NULL COMMENT '成员姓名',
  `relation` varchar(20) NOT NULL COMMENT '关系：SPOUSE配偶 FATHER父 MOTHER母 CHILD子女 SIBLING兄弟姐妹 OTHER其他',
  `birthday` date DEFAULT NULL COMMENT '出生日期',
  `work_unit` varchar(100) DEFAULT NULL COMMENT '工作单位',
  `mobile_cipher` varchar(200) DEFAULT NULL COMMENT '联系电话密文',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_employee_family_employee_id` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='家庭成员';


-- ---------------------------------------------------------------------
-- 5. employee_bank_account 银行卡与工资账户
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employee_bank_account` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `bank_name` varchar(50) NOT NULL COMMENT '开户行名称',
  `branch_name` varchar(100) DEFAULT NULL COMMENT '开户支行',
  `account_cipher` varchar(200) NOT NULL COMMENT '银行卡号密文',
  `account_hash` varchar(64) NOT NULL COMMENT '银行卡号SHA-256，用于查重',
  `account_mask` varchar(30) NOT NULL COMMENT '卡号脱敏值，如 6222****1234',
  `is_primary` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否主账户：0否 1是（每人仅一个）',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_employee_bank_account_employee_id` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='银行卡与工资账户';


-- ---------------------------------------------------------------------
-- 6. employee_certificate 证照（支持到期预警）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employee_certificate` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `cert_type` varchar(30) NOT NULL COMMENT '证照类型：SPECIAL_OPERATION特种作业 FORKLIFT叉车 ELECTRIC电工 WELDING焊工 OTHER其他',
  `cert_no` varchar(50) DEFAULT NULL COMMENT '证照编号',
  `issue_date` date DEFAULT NULL COMMENT '发证日期',
  `expire_date` date DEFAULT NULL COMMENT '到期日期；为空表示长期有效',
  `cert_file_path` varchar(300) DEFAULT NULL COMMENT '证照扫描件路径',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_employee_certificate_employee_id` (`employee_id`),
  KEY `idx_employee_certificate_expire_date` (`expire_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='证照管理';


-- ---------------------------------------------------------------------
-- 7. employee_attachment 档案附件
-- 文件存对象存储/文件服务器，库里只存路径，禁止存二进制。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employee_attachment` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `attach_type` varchar(30) NOT NULL COMMENT '附件类型：ID_CARD身份证 EDUCATION学历 HEALTH_CHECK体检报告 ONBOARD_FORM入职登记表 CONTRACT合同 OTHER其他',
  `file_name` varchar(200) NOT NULL COMMENT '原始文件名',
  `file_path` varchar(300) NOT NULL COMMENT '存储路径（相对路径，不含域名）',
  `file_size` bigint unsigned DEFAULT NULL COMMENT '文件大小（字节）',
  `file_hash` varchar(64) DEFAULT NULL COMMENT '文件SHA-256，用于去重',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_employee_attachment_employee_id` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='档案附件';


-- ---------------------------------------------------------------------
-- 8. employee_change 员工异动流水
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employee_change` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `change_type` varchar(20) NOT NULL COMMENT '异动类型，枚举同 employment.change_type',
  `effective_date` date NOT NULL COMMENT '生效日期',
  `before_data` json DEFAULT NULL COMMENT '变更前（组织/职位/职级/薪档/汇报人）',
  `after_data` json DEFAULT NULL COMMENT '变更后',
  `change_order_no` varchar(30) DEFAULT NULL COMMENT '异动单号',
  `operator_id` bigint unsigned NOT NULL COMMENT '操作人ID',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_employee_change_employee_id_effective_date` (`employee_id`,`effective_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='员工异动流水';


-- ---------------------------------------------------------------------
-- 9. onboard_order 入职单
-- 生效后：生成 employee + employment + 合同 + 社保参保
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `onboard_order` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `order_no` varchar(30) NOT NULL COMMENT '单据号',
  `employee_id` bigint unsigned DEFAULT NULL COMMENT '员工ID；入职登记时可能尚未建档',
  `emp_name` varchar(50) NOT NULL COMMENT '姓名',
  `id_card_cipher` varchar(200) DEFAULT NULL COMMENT '身份证密文',
  `entry_date` date NOT NULL COMMENT '入职日期',
  `organization_id` bigint unsigned NOT NULL COMMENT '入职组织ID',
  `position_id` bigint unsigned NOT NULL COMMENT '入职职位ID',
  `grade_id` bigint unsigned NOT NULL COMMENT '定级职级ID',
  `employment_nature` varchar(20) NOT NULL COMMENT '用工性质，枚举同 employee.employment_nature',
  `contract_type` varchar(20) DEFAULT NULL COMMENT '合同类型，枚举同 labor_contract.contract_type',
  `probation_months` tinyint DEFAULT NULL COMMENT '试用期月数',
  `approval_instance_id` bigint unsigned DEFAULT NULL COMMENT '审批实例ID',
  `approval_status` varchar(20) NOT NULL DEFAULT 'DRAFT' COMMENT '审批状态：DRAFT草稿 SUBMITTED已提交 APPROVING审批中 APPROVED已通过 REJECTED已驳回 CANCELLED已撤销',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_onboard_order_order_no` (`order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='入职单';


-- ---------------------------------------------------------------------
-- 10. regular_order 转正单
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `regular_order` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `order_no` varchar(30) NOT NULL COMMENT '单据号',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `probation_end_date` date DEFAULT NULL COMMENT '试用期结束日期',
  `assess_result` varchar(20) DEFAULT NULL COMMENT '考核结果：PASS通过 FAIL不通过 EXTEND延长',
  `regular_date` date NOT NULL COMMENT '转正日期',
  `approval_instance_id` bigint unsigned DEFAULT NULL COMMENT '审批实例ID',
  `approval_status` varchar(20) NOT NULL DEFAULT 'DRAFT' COMMENT '审批状态，枚举同 onboard_order.approval_status',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_regular_order_order_no` (`order_no`),
  KEY `idx_regular_order_employee_id` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='转正单';


-- ---------------------------------------------------------------------
-- 11. resign_order 离职单
-- 生效后：改 employee_status、关 employment（end_date）、停社保、停账号
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `resign_order` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `order_no` varchar(30) NOT NULL COMMENT '单据号',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `resign_type` varchar(20) NOT NULL COMMENT '离职类型：ACTIVE主动 PASSIVE被动',
  `resign_reason_code` varchar(20) DEFAULT NULL COMMENT '离职原因编码，关联字典',
  `last_work_date` date NOT NULL COMMENT '最后工作日',
  `handover_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '交接状态：PENDING未开始 DOING进行中 DONE已完成',
  `approval_instance_id` bigint unsigned DEFAULT NULL COMMENT '审批实例ID',
  `approval_status` varchar(20) NOT NULL DEFAULT 'DRAFT' COMMENT '审批状态，枚举同 onboard_order.approval_status',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_resign_order_order_no` (`order_no`),
  KEY `idx_resign_order_employee_id` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='离职单';


-- ---------------------------------------------------------------------
-- 12. labor_contract 劳动合同
-- renew_count 连续两次固定期限后应提示签无固定期限（HR-CON-04）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `labor_contract` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `contract_no` varchar(50) DEFAULT NULL COMMENT '合同编号',
  `contract_type` varchar(20) NOT NULL COMMENT '合同类型：FIXED固定期限 UNFIXED无固定期限 TASK以完成一定工作为期限 LABOR劳务 INTERN实习 REHIRE返聘',
  `sign_date` date NOT NULL COMMENT '签订日期',
  `start_date` date NOT NULL COMMENT '合同开始日',
  `end_date` date DEFAULT NULL COMMENT '合同结束日；无固定期限为 NULL',
  `probation_start_date` date DEFAULT NULL COMMENT '试用期开始',
  `probation_end_date` date DEFAULT NULL COMMENT '试用期结束',
  `renew_count` tinyint NOT NULL DEFAULT '0' COMMENT '续签次数；0为初签，连续两次后应提示无固定期限',
  `parent_contract_id` bigint unsigned DEFAULT NULL COMMENT '上一份合同ID',
  `status` varchar(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '状态：ACTIVE生效 EXPIRED到期 TERMINATED解除 CANCELLED作废',
  `file_path` varchar(300) DEFAULT NULL COMMENT '合同扫描件路径',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_labor_contract_employee_id` (`employee_id`),
  KEY `idx_labor_contract_end_date` (`end_date`),
  CONSTRAINT `ck_labor_contract_date` CHECK (`end_date` IS NULL OR `end_date` >= `start_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='劳动合同';


-- ---------------------------------------------------------------------
-- 13. labor_contract_change 合同变更协议
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `labor_contract_change` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `contract_id` bigint unsigned NOT NULL COMMENT '合同ID',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `change_type` varchar(20) NOT NULL COMMENT '变更类型：POSITION岗位 SALARY薪资 TERM期限 OTHER其他',
  `change_content` varchar(500) NOT NULL COMMENT '变更内容',
  `effective_date` date NOT NULL COMMENT '生效日期',
  `file_path` varchar(300) DEFAULT NULL COMMENT '变更协议扫描件路径',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_labor_contract_change_contract_id` (`contract_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='合同变更协议';


-- ---------------------------------------------------------------------
-- 14. contract_renewal_remind 合同到期预警任务
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `contract_renewal_remind` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `contract_id` bigint unsigned NOT NULL COMMENT '合同ID',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `remind_date` date NOT NULL COMMENT '提醒日期',
  `remind_level` tinyint NOT NULL COMMENT '提醒档位：90提前90天 60提前60天 30提前30天',
  `is_sent` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否已发送：0否 1是',
  `sent_at` datetime(3) DEFAULT NULL COMMENT '发送时间',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_contract_renewal_remind_contract_id_remind_level` (`contract_id`,`remind_level`),
  KEY `idx_contract_renewal_remind_remind_date` (`remind_date`,`is_sent`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='合同到期预警任务';

SET FOREIGN_KEY_CHECKS = 1;
