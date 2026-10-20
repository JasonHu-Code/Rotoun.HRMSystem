-- =====================================================================
-- HR 人事管理系统 · 建表脚本 04：假期、薪酬、社保
-- 数据库：rt-hrms    MySQL 8.0+    utf8mb4 / utf8mb4_general_ci
-- 依据：HR系统_数据库设计_V0.1.md 第九章、第十章、第十一章
-- 表数：17（假期4 + 薪酬11 + 社保2）
--
-- 注意：
--   1. salary_detail_item 必须存 item_name 快照，防止项目改名后历史工资条失真。
--   2. 薪资数据暂缺（业务确认），grade_salary_standard 先建表不填值。
--   3. 倍率只在 attendance_rule，薪酬模块不另配一套。
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ======================= 一、假期 =======================

-- ---------------------------------------------------------------------
-- 1. leave_type 假期类型
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `leave_type` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `type_code` varchar(30) NOT NULL COMMENT '假期类型编码',
  `type_name` varchar(50) NOT NULL COMMENT '假期类型名称',
  `is_paid` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否带薪：0否 1是',
  `is_statutory` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否法定假（年假/婚丧产等）：0公司假 1法定假',
  `min_unit` varchar(20) NOT NULL DEFAULT 'HOUR' COMMENT '最小请假单位：HOUR小时 HALF_DAY半天 DAY天',
  `need_attachment_days` decimal(4,1) DEFAULT NULL COMMENT '超过该天数需上传证明；NULL 表示不需要',
  `max_days_per_year` decimal(5,1) DEFAULT NULL COMMENT '年上限天数；NULL 表示不限',
  `sort_no` int NOT NULL DEFAULT '0' COMMENT '排序号',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_leave_type_type_code` (`type_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='假期类型';


-- ---------------------------------------------------------------------
-- 2. leave_quota 假期额度（按人按年）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `leave_quota` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `organization_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属组织快照；写入时取自 employment，保证历史归属不随调岗变化',
  `legal_entity_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属法人快照；写入时取自 employment.legal_entity_id',
  `leave_type_id` bigint unsigned NOT NULL COMMENT '假期类型ID',
  `quota_year` smallint NOT NULL COMMENT '额度年度',
  `total_days` decimal(6,2) NOT NULL DEFAULT '0.00' COMMENT '年度总天数',
  `used_days` decimal(6,2) NOT NULL DEFAULT '0.00' COMMENT '已使用天数',
  `remain_days` decimal(6,2) NOT NULL DEFAULT '0.00' COMMENT '剩余天数',
  `carried_over_days` decimal(6,2) NOT NULL DEFAULT '0.00' COMMENT '上年结转天数',
  `expire_date` date DEFAULT NULL COMMENT '结转部分到期日；NULL 表示不结转',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_leave_quota_organization_id` (`organization_id`),
  KEY `idx_leave_quota_legal_entity_id` (`legal_entity_id`),
  UNIQUE KEY `uk_leave_quota_employee_id_leave_type_id_quota_year` (`employee_id`,`leave_type_id`,`quota_year`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='假期额度';


-- ---------------------------------------------------------------------
-- 3. leave_quota_log 假期额度流水
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `leave_quota_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `leave_type_id` bigint unsigned NOT NULL COMMENT '假期类型ID',
  `quota_year` smallint NOT NULL COMMENT '额度年度',
  `change_type` varchar(20) NOT NULL COMMENT '变动类型：GRANT发放 USE使用 ADJUST调整 CARRY_OVER结转 EXPIRE清零',
  `change_days` decimal(6,2) NOT NULL COMMENT '变动天数，正数增加 负数减少',
  `before_remain` decimal(6,2) DEFAULT NULL COMMENT '变动前剩余',
  `after_remain` decimal(6,2) DEFAULT NULL COMMENT '变动后剩余',
  `ref_order_no` varchar(30) DEFAULT NULL COMMENT '关联单据号',
  `remark` varchar(200) DEFAULT NULL COMMENT '备注',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_leave_quota_log_employee_id_leave_type_id` (`employee_id`,`leave_type_id`,`quota_year`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='假期额度流水';


-- ---------------------------------------------------------------------
-- 4. leave_apply 请假单
-- 跨假期类型时自动拆分，生成多条明细（明细字段直接冗余在本表按行存）。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `leave_apply` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `order_no` varchar(30) NOT NULL COMMENT '单据号',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `organization_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属组织快照；写入时取自 employment，保证历史归属不随调岗变化',
  `legal_entity_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属法人快照；写入时取自 employment.legal_entity_id',
  `leave_type_id` bigint unsigned NOT NULL COMMENT '假期类型ID',
  `start_time` datetime NOT NULL COMMENT '请假开始时间',
  `end_time` datetime NOT NULL COMMENT '请假结束时间',
  `leave_days` decimal(6,2) NOT NULL DEFAULT '0.00' COMMENT '请假天数',
  `leave_hours` decimal(6,2) NOT NULL DEFAULT '0.00' COMMENT '请假小时数',
  `reason` varchar(500) DEFAULT NULL COMMENT '请假事由',
  `attach_path` varchar(300) DEFAULT NULL COMMENT '证明材料路径',
  `approval_instance_id` bigint unsigned DEFAULT NULL COMMENT '审批实例ID',
  `approval_status` varchar(20) NOT NULL DEFAULT 'DRAFT' COMMENT '审批状态：DRAFT草稿 SUBMITTED已提交 APPROVING审批中 APPROVED已通过 REJECTED已驳回 CANCELLED已撤销',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_leave_apply_organization_id` (`organization_id`),
  KEY `idx_leave_apply_legal_entity_id` (`legal_entity_id`),
  UNIQUE KEY `uk_leave_apply_order_no` (`order_no`),
  KEY `idx_leave_apply_employee_id_start_time` (`employee_id`,`start_time`),
  KEY `idx_leave_apply_approval_status` (`approval_status`),
  CONSTRAINT `ck_leave_apply_time` CHECK (`end_time` > `start_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='请假单';


-- ======================= 二、薪酬 =======================

-- ---------------------------------------------------------------------
-- 5. salary_item 薪资项目
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `salary_item` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `item_code` varchar(30) NOT NULL COMMENT '项目编码',
  `item_name` varchar(50) NOT NULL COMMENT '项目名称',
  `item_type` varchar(20) NOT NULL COMMENT '项目类型：INCOME收入项 DEDUCTION扣款项 EMPLOYER_COST公司承担项',
  `calc_type` varchar(20) NOT NULL COMMENT '计算方式：FIXED固定 FORMULA公式 ATTENDANCE考勤联动 PIECE计件 MANUAL手工',
  `formula_expr` varchar(500) DEFAULT NULL COMMENT '计算公式，calc_type=FORMULA 时使用',
  `is_taxable` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否计入计税基数：0否 1是',
  `is_insurance_base` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否计入社保基数：0否 1是',
  `sort_no` int NOT NULL DEFAULT '0' COMMENT '计算顺序；有依赖关系时顺序很重要',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_salary_item_item_code` (`item_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='薪资项目';


-- ---------------------------------------------------------------------
-- 6. salary_plan 薪资方案（按法人/业态配置）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `salary_plan` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `plan_code` varchar(30) NOT NULL COMMENT '方案编码',
  `plan_name` varchar(50) NOT NULL COMMENT '方案名称',
  `legal_entity_id` bigint unsigned NOT NULL COMMENT '适用法人ID',
  `effective_from` date NOT NULL COMMENT '生效开始日期',
  `effective_to` date NOT NULL DEFAULT '9999-12-31' COMMENT '生效结束日期',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_salary_plan_plan_code` (`plan_code`),
  KEY `idx_salary_plan_legal_entity_id` (`legal_entity_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='薪资方案';


-- ---------------------------------------------------------------------
-- 7. salary_plan_item 方案包含的薪资项目
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `salary_plan_item` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `plan_id` bigint unsigned NOT NULL COMMENT '方案ID',
  `item_id` bigint unsigned NOT NULL COMMENT '薪资项目ID',
  `sort_no` int NOT NULL DEFAULT '0' COMMENT '排序号',
  `default_value` decimal(14,2) DEFAULT NULL COMMENT '默认值',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_salary_plan_item_plan_id_item_id` (`plan_id`,`item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='薪资方案项目';


-- ---------------------------------------------------------------------
-- 8. grade_salary_standard 职级薪档标准
-- 【薪资数据暂缺】表先建，上线前由财务数据回填。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `grade_salary_standard` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `grade_id` bigint unsigned NOT NULL COMMENT '职级ID',
  `salary_plan_id` bigint unsigned NOT NULL COMMENT '薪资方案ID',
  `step_no` tinyint NOT NULL COMMENT '薪档序号，从1开始',
  `base_salary` decimal(14,2) NOT NULL COMMENT '该档基本工资',
  `effective_from` date NOT NULL COMMENT '生效开始日期',
  `effective_to` date NOT NULL DEFAULT '9999-12-31' COMMENT '生效结束日期',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_grade_salary_standard_grade_plan_step` (`grade_id`,`salary_plan_id`,`step_no`,`effective_from`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='职级薪档标准';


-- ---------------------------------------------------------------------
-- 9. social_insurance_plan 社保公积金方案（按参保城市）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `social_insurance_plan` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `plan_name` varchar(50) NOT NULL COMMENT '方案名称',
  `city_code` varchar(20) NOT NULL COMMENT '参保城市编码',
  `insurance_year` smallint NOT NULL COMMENT '社保年度，如 2026',
  `effective_from` date NOT NULL COMMENT '生效开始日期',
  `effective_to` date NOT NULL DEFAULT '9999-12-31' COMMENT '生效结束日期',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_social_insurance_plan_city_code_year` (`city_code`,`insurance_year`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='社保公积金方案';


-- ---------------------------------------------------------------------
-- 10. social_insurance_plan_item 社保明细项（比例与基数上下限）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `social_insurance_plan_item` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `plan_id` bigint unsigned NOT NULL COMMENT '社保方案ID',
  `insurance_type` varchar(30) NOT NULL COMMENT '险种：PENSION养老 MEDICAL医疗 UNEMPLOYMENT失业 INJURY工伤 MATERNITY生育 HOUSING_FUND公积金',
  `person_rate` decimal(6,4) NOT NULL DEFAULT '0.0000' COMMENT '个人比例',
  `company_rate` decimal(6,4) NOT NULL DEFAULT '0.0000' COMMENT '公司比例',
  `base_min` decimal(14,2) DEFAULT NULL COMMENT '基数下限',
  `base_max` decimal(14,2) DEFAULT NULL COMMENT '基数上限',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_social_insurance_plan_item_plan_id_insurance_type` (`plan_id`,`insurance_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='社保方案明细项';


-- ---------------------------------------------------------------------
-- 11. salary_calc_batch 算薪批次
-- 试算与正式分开，试算不产生正式数据。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `salary_calc_batch` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `batch_no` varchar(30) NOT NULL COMMENT '批次号',
  `close_month` varchar(7) NOT NULL COMMENT '薪资月份，格式 yyyy-MM',
  `legal_entity_id` bigint unsigned NOT NULL COMMENT '法人ID',
  `calc_status` varchar(20) NOT NULL DEFAULT 'DRAFT' COMMENT '状态：DRAFT试算 CALCULATING计算中 CALCULATED已计算 CONFIRMED已封账',
  `calc_by` bigint unsigned DEFAULT NULL COMMENT '计算人ID',
  `calc_at` datetime(3) DEFAULT NULL COMMENT '计算时间',
  `employee_count` int NOT NULL DEFAULT '0' COMMENT '涉及人数',
  `total_amount` decimal(16,2) NOT NULL DEFAULT '0.00' COMMENT '应发合计',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_salary_calc_batch_batch_no` (`batch_no`),
  KEY `idx_salary_calc_batch_legal_entity_id_close_month` (`legal_entity_id`,`close_month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='算薪批次';


-- ---------------------------------------------------------------------
-- 12. salary_detail 薪资明细头
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `salary_detail` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `batch_no` varchar(30) NOT NULL COMMENT '批次号',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `organization_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属组织快照；写入时取自 employment，保证历史归属不随调岗变化',
  `close_month` varchar(7) NOT NULL COMMENT '薪资月份，格式 yyyy-MM',
  `legal_entity_id` bigint unsigned NOT NULL COMMENT '法人ID',
  `gross_amount` decimal(14,2) NOT NULL DEFAULT '0.00' COMMENT '应发合计',
  `deduction_amount` decimal(14,2) NOT NULL DEFAULT '0.00' COMMENT '扣款合计',
  `net_amount` decimal(14,2) NOT NULL DEFAULT '0.00' COMMENT '实发合计',
  `is_formal` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否正式数据：0试算 1正式',
  `is_locked` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否封账：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_salary_detail_organization_id` (`organization_id`),
  KEY `idx_salary_detail_legal_entity_id` (`legal_entity_id`),
  KEY `idx_salary_detail_batch_no` (`batch_no`),
  KEY `idx_salary_detail_employee_id_close_month` (`employee_id`,`close_month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='薪资明细头';


-- ---------------------------------------------------------------------
-- 13. salary_detail_item 薪资明细行
-- 【必须存 item_name 快照】项目改名后历史工资条不能变。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `salary_detail_item` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `detail_id` bigint unsigned NOT NULL COMMENT '明细头ID',
  `item_id` bigint unsigned NOT NULL COMMENT '薪资项目ID（引用，可能已被改名）',
  `item_code` varchar(30) NOT NULL COMMENT '项目编码快照',
  `item_name` varchar(50) NOT NULL COMMENT '项目名称快照（审计要求，不可省）',
  `item_type` varchar(20) NOT NULL COMMENT '项目类型快照：INCOME收入项 DEDUCTION扣款项 EMPLOYER_COST公司承担项',
  `amount` decimal(14,2) NOT NULL DEFAULT '0.00' COMMENT '金额',
  `calc_desc` varchar(300) DEFAULT NULL COMMENT '计算说明，如「产量1200件×单价0.5」',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_salary_detail_item_detail_id` (`detail_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='薪资明细行';


-- ---------------------------------------------------------------------
-- 14. piece_rate 工序单价表
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `piece_rate` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `product_code` varchar(50) NOT NULL COMMENT '产品编码',
  `product_name` varchar(100) DEFAULT NULL COMMENT '产品名称',
  `process_code` varchar(50) NOT NULL COMMENT '工序编码',
  `process_name` varchar(100) DEFAULT NULL COMMENT '工序名称',
  `unit_price` decimal(10,4) NOT NULL COMMENT '计件单价（元/件）',
  `legal_entity_id` bigint unsigned DEFAULT NULL COMMENT '适用法人ID；NULL 表示全集团',
  `effective_from` date NOT NULL COMMENT '生效开始日期',
  `effective_to` date NOT NULL DEFAULT '9999-12-31' COMMENT '生效结束日期',
  `version_no` int NOT NULL DEFAULT '1' COMMENT '版本号',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_piece_rate_product_code_process_code` (`product_code`,`process_code`,`effective_from`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='工序单价表';


-- ---------------------------------------------------------------------
-- 15. piece_output 计件产量记录
-- 必须能追溯到「某人某天做了哪道工序多少件」，
-- 否则车间主任问「这个数怎么算的」答不出来。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `piece_output` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `organization_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属组织快照；写入时取自 employment，保证历史归属不随调岗变化',
  `legal_entity_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属法人快照；写入时取自 employment.legal_entity_id',
  `work_date` date NOT NULL COMMENT '生产日期',
  `product_code` varchar(50) NOT NULL COMMENT '产品编码',
  `process_code` varchar(50) NOT NULL COMMENT '工序编码',
  `output_qty` decimal(12,2) NOT NULL COMMENT '完成数量',
  `unit_price` decimal(10,4) NOT NULL COMMENT '结算单价（录入时的单价快照）',
  `amount` decimal(14,2) NOT NULL COMMENT '计件金额 = output_qty × unit_price',
  `piece_rate_id` bigint unsigned DEFAULT NULL COMMENT '引用的单价记录ID',
  `order_no` varchar(50) DEFAULT NULL COMMENT '关联生产工单号',
  `data_source` varchar(20) NOT NULL DEFAULT 'MANUAL' COMMENT '数据来源：MANUAL手工录入 IMPORT批量导入 MES系统对接',
  `close_month` varchar(7) DEFAULT NULL COMMENT '归属薪资月份，格式 yyyy-MM',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_piece_output_organization_id` (`organization_id`),
  KEY `idx_piece_output_legal_entity_id` (`legal_entity_id`),
  KEY `idx_piece_output_employee_id_work_date` (`employee_id`,`work_date`),
  KEY `idx_piece_output_close_month` (`close_month`),
  KEY `idx_piece_output_order_no` (`order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='计件产量记录';


-- ======================= 三、社保 =======================

-- ---------------------------------------------------------------------
-- 16. social_insurance_account 员工参保账户
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `social_insurance_account` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `plan_id` bigint unsigned NOT NULL COMMENT '社保方案ID',
  `insurance_no` varchar(50) DEFAULT NULL COMMENT '社保账号',
  `join_date` date NOT NULL COMMENT '参保日期',
  `quit_date` date DEFAULT NULL COMMENT '停保日期',
  `base_amount` decimal(14,2) DEFAULT NULL COMMENT '当前缴费基数',
  `status` varchar(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '状态：ACTIVE参保中 SUSPENDED暂停 QUIT已停保',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_social_insurance_account_employee_id` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='员工参保账户';


-- ---------------------------------------------------------------------
-- 17. social_insurance_change 社保增减员与基数调整
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `social_insurance_change` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `change_type` varchar(20) NOT NULL COMMENT '变动类型：INCREASE增员 DECREASE减员 BASE_ADJUST基数调整',
  `effective_month` varchar(7) NOT NULL COMMENT '生效月份，格式 yyyy-MM',
  `before_base` decimal(14,2) DEFAULT NULL COMMENT '变动前基数',
  `after_base` decimal(14,2) DEFAULT NULL COMMENT '变动后基数',
  `order_no` varchar(30) DEFAULT NULL COMMENT '关联单号',
  `remark` varchar(200) DEFAULT NULL COMMENT '备注',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_social_insurance_change_employee_id_effective_month` (`employee_id`,`effective_month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='社保增减员与基数调整';

SET FOREIGN_KEY_CHECKS = 1;
