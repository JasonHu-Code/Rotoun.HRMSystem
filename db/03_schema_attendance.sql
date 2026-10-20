-- =====================================================================
-- HR 人事管理系统 · 建表脚本 03：考勤与排班
-- 数据库：rt-hrms    MySQL 8.0+    utf8mb4 / utf8mb4_general_ci
-- 依据：HR系统_数据库设计_V0.1.md 第八章、HR系统_考勤计算引擎设计_V0.1.md
-- 表数：16
--
-- 三条硬约束（改表前先读）：
--   1. attendance_punch_raw 只追加，永不修改。补卡走 attendance_appeal。
--   2. attendance_day_result 必须存 rule_version / calendar_version 快照。
--   3. work_calendar_override 不存 day_type，只表达"是否安排上班"。
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- 1. attendance_rule 考勤规则（分层配置）
-- 继承链：EMPLOYEE -> TEAM -> DEPARTMENT -> COMPANY -> GROUP
-- 整条命中，不做字段级合并。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `attendance_rule` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `rule_name` varchar(50) NOT NULL COMMENT '规则名称',
  `scope_type` varchar(20) NOT NULL COMMENT '作用域类型：GROUP集团 COMPANY公司 DEPARTMENT部门 TEAM班组 EMPLOYEE个人',
  `scope_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '作用域ID；GROUP 固定为 0',
  `rule_version` int NOT NULL DEFAULT '1' COMMENT '规则版本号',
  `effective_from` date NOT NULL COMMENT '生效开始日期',
  `effective_to` date NOT NULL DEFAULT '9999-12-31' COMMENT '生效结束日期',
  `late_tolerance_min` int NOT NULL DEFAULT '0' COMMENT '迟到容差（分钟），默认0即无容差；可按公司调整',
  `early_tolerance_min` int NOT NULL DEFAULT '0' COMMENT '早退容差（分钟），默认0即无容差；可按公司调整',
  `absent_threshold_min` int NOT NULL DEFAULT '240' COMMENT '旷工判定阈值（分钟）：应出勤但出勤不足该值时判旷工',
  `overtime_need_apply` tinyint(1) NOT NULL DEFAULT '1' COMMENT '加班是否需要申请：0否 1是。业务口径为事后申请——先加班后填报',
  `overtime_month_limit_hour` decimal(6,2) DEFAULT '36.00' COMMENT '月加班上限（小时），按公司配置；36小时为法定上限，超限仅预警不硬拦',
  `overtime_round_unit_min` int NOT NULL DEFAULT '60' COMMENT '加班最小计量单位（分钟），默认60即1小时',
  `overtime_round_type` varchar(10) NOT NULL DEFAULT 'CEIL' COMMENT '加班取整方式：CEIL向上 FLOOR向下 ROUND四舍五入',
  `workday_overtime_rate` decimal(6,4) NOT NULL DEFAULT '1.5000' COMMENT '工作日加班倍率',
  `restday_overtime_rate` decimal(6,4) NOT NULL DEFAULT '2.0000' COMMENT '休息日加班倍率',
  `holiday_overtime_rate` decimal(6,4) NOT NULL DEFAULT '3.0000' COMMENT '法定节假日加班倍率',
  `min_leave_unit` varchar(20) NOT NULL DEFAULT 'HOUR' COMMENT '请假最小单位：HOUR小时 HALF_DAY半天 DAY天',
  `appeal_month_limit` int NOT NULL DEFAULT '3' COMMENT '每人每月补卡次数上限，默认3次；超限不予受理',
  `appeal_window_days` int NOT NULL DEFAULT '3' COMMENT '申诉受理期（工作日）；超期后不再受理，已判定的旷工不再变更',
  `allow_mobile_punch` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否允许手机打卡：0否 1是',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：0否 1是',
  `remark` varchar(500) DEFAULT NULL COMMENT '备注',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_attendance_rule_scope_version_from` (`scope_type`,`scope_id`,`rule_version`,`effective_from`),
  KEY `idx_attendance_rule_scope` (`scope_type`,`scope_id`,`effective_from`),
  CONSTRAINT `ck_attendance_rule_date` CHECK (`effective_to` >= `effective_from`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='考勤规则（分层配置）';


-- ---------------------------------------------------------------------
-- 2. shift 班次模板
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `shift` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `shift_code` varchar(30) NOT NULL COMMENT '班次编码',
  `shift_name` varchar(50) NOT NULL COMMENT '班次名称，如「白班 08:00-20:00」',
  `legal_entity_id` bigint unsigned DEFAULT NULL COMMENT '所属法人ID；NULL 表示集团通用',
  `is_cross_day` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否跨天（夜班）：0否 1是',
  `cross_day_rule` varchar(20) NOT NULL DEFAULT 'START_DAY' COMMENT '跨天归属：START_DAY归上班日 END_DAY归下班日',
  `standard_work_hours` decimal(6,2) NOT NULL DEFAULT '8.00' COMMENT '标准工时（小时）',
  `rest_minutes` int NOT NULL DEFAULT '60' COMMENT '班内休息时长（分钟），仅单段班扣减',
  `punch_count` tinyint NOT NULL DEFAULT '2' COMMENT '应打卡次数',
  `late_tolerance_min` int DEFAULT NULL COMMENT '迟到容差；NULL 表示继承规则层',
  `early_tolerance_min` int DEFAULT NULL COMMENT '早退容差；NULL 表示继承规则层',
  `is_flexible` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否弹性班：0否 1是',
  `flexible_core_start` time DEFAULT NULL COMMENT '弹性核心时段开始（须在岗）',
  `flexible_core_end` time DEFAULT NULL COMMENT '弹性核心时段结束',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shift_shift_code` (`shift_code`),
  KEY `idx_shift_legal_entity_id` (`legal_entity_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='班次模板';


-- ---------------------------------------------------------------------
-- 3. shift_segment 班次时段（支持多段班）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `shift_segment` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `shift_id` bigint unsigned NOT NULL COMMENT '班次ID',
  `segment_no` tinyint NOT NULL COMMENT '段序号，从1开始',
  `work_start_time` time NOT NULL COMMENT '上班时刻',
  `work_end_time` time NOT NULL COMMENT '下班时刻',
  `is_cross_day` tinyint(1) NOT NULL DEFAULT '0' COMMENT '本段是否跨天：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shift_segment_shift_id_segment_no` (`shift_id`,`segment_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='班次时段';


-- ---------------------------------------------------------------------
-- 4. employee_shift_binding 个人长期班次（特殊工时备案）
-- 个人时段差异只能通过这张表产生，不允许给个人复制一套规则。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employee_shift_binding` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `shift_id` bigint unsigned NOT NULL COMMENT '绑定的班次ID',
  `reason_type` varchar(30) NOT NULL COMMENT '原因类型：LACTATION哺乳期 PREGNANT孕期 INJURY工伤 DISABILITY残疾 STATIONED驻外 DUTY值班岗 OTHER其他',
  `reason_desc` varchar(200) DEFAULT NULL COMMENT '原因补充说明',
  `start_date` date NOT NULL COMMENT '生效开始日期',
  `end_date` date DEFAULT NULL COMMENT '生效结束日期；NULL 表示长期',
  `approval_instance_id` bigint unsigned DEFAULT NULL COMMENT '审批实例ID；必须审批',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_employee_shift_binding_employee_id_start_date` (`employee_id`,`start_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='个人长期班次（特殊工时备案）';


-- ---------------------------------------------------------------------
-- 5. shift_schedule 排班表
-- 个人"考勤时段与工作日"的真正来源。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `shift_schedule` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `work_date` date NOT NULL COMMENT '排班日期',
  `shift_id` bigint unsigned DEFAULT NULL COMMENT '班次ID；休息排班时可为 NULL',
  `schedule_type` varchar(20) NOT NULL DEFAULT 'ROTATION' COMMENT '排班来源：ROTATION轮班生成 MANUAL手工 CHANGE改班',
  `change_order_no` varchar(30) DEFAULT NULL COMMENT '改班单号',
  `is_rest` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否休息：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shift_schedule_employee_id_work_date` (`employee_id`,`work_date`),
  KEY `idx_shift_schedule_work_date` (`work_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='排班表';


-- ---------------------------------------------------------------------
-- 6. work_calendar 工作日历（法定属性，公司级）
-- day_type 只能来自这张表，个人不可覆盖。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `work_calendar` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `legal_entity_id` bigint unsigned NOT NULL COMMENT '法人ID；不同厂区可不同',
  `calendar_date` date NOT NULL COMMENT '日期',
  `day_type` varchar(20) NOT NULL COMMENT '日期属性：WORKDAY工作日 RESTDAY休息日 HOLIDAY法定节假日',
  `holiday_name` varchar(50) DEFAULT NULL COMMENT '节假日名称',
  `calendar_version` int NOT NULL DEFAULT '1' COMMENT '日历版本号',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_work_calendar_legal_entity_id_calendar_date_version` (`legal_entity_id`,`calendar_date`,`calendar_version`),
  KEY `idx_work_calendar_calendar_date` (`calendar_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='工作日历（法定属性）';


-- ---------------------------------------------------------------------
-- 7. work_calendar_override 个人日历覆盖
-- 【刻意不存 day_type】只表达"这天是否安排他上班"。
-- 一旦允许个人覆盖法定属性，就等于允许把法定节假日改写成工作日，
-- 3倍加班费变1.5倍，劳动仲裁必输。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `work_calendar_override` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `calendar_date` date NOT NULL COMMENT '日期',
  `arrange_work` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否安排上班：0否 1是',
  `reason` varchar(200) NOT NULL COMMENT '原因（必填，用于事后举证）',
  `order_no` varchar(30) DEFAULT NULL COMMENT '关联单据号',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_work_calendar_override_employee_id_calendar_date` (`employee_id`,`calendar_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='个人日历覆盖（仅安排上班，不改法定属性）';


-- ---------------------------------------------------------------------
-- 8. attendance_punch_raw 原始打卡流水
-- 【只追加，永不修改】所有更正走 attendance_appeal。
-- 唯一索引用于设备重复上报去重；emp_no 允许为空（未认领）。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `attendance_punch_raw` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `emp_no` varchar(20) DEFAULT NULL COMMENT '工号；未匹配到员工时为 NULL',
  `device_user_no` varchar(30) NOT NULL DEFAULT '' COMMENT '设备用户号（得力 user_id / 设备工号）',
  `punch_time` datetime NOT NULL COMMENT '打卡时间，精确到秒',
  `punch_date` date NOT NULL COMMENT '打卡日期（冗余，用于索引与按月分区）',
  `terminal_sn` varchar(50) NOT NULL DEFAULT '' COMMENT '设备SN；手机打卡为设备ID；补签为 apply',
  `punch_type` varchar(20) NOT NULL COMMENT '打卡方式：FACE人脸 FINGERPRINT指纹 CARD刷卡 PASSWORD密码 MOBILE_GPS MOBILE_WIFI FIELD外勤 REISSUE补签申请 FLEXIBLE自动补卡',
  `punch_source` varchar(20) NOT NULL COMMENT '数据来源：DEVICE_IMPORT设备文件导入 PUSH设备推送 CLOUD_PULL云平台拉取 PROCESSING中间件轮询 MANUAL手工',
  `import_batch_id` bigint unsigned DEFAULT NULL COMMENT '导入批次ID；非文件导入为 NULL',
  `raw_seq` varchar(50) DEFAULT NULL COMMENT '厂商原始记录ID，用于去重',
  `is_claimed` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否已匹配到员工：0否 1是',
  `claim_remark` varchar(200) DEFAULT NULL COMMENT '未认领原因',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是（业务上禁止删除，仅归档用）',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_attendance_punch_raw_dedup` (`punch_source`,`terminal_sn`,`device_user_no`,`punch_time`),
  KEY `idx_attendance_punch_raw_emp_no_punch_date` (`emp_no`,`punch_date`),
  KEY `idx_attendance_punch_raw_punch_date` (`punch_date`),
  KEY `idx_attendance_punch_raw_is_claimed` (`is_claimed`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='原始打卡流水（只追加）';


-- ---------------------------------------------------------------------
-- 9. attendance_punch_import_batch 打卡数据导入批次
-- v1.0 的打卡数据入口（HR-ATT-29）。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `attendance_punch_import_batch` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `batch_no` varchar(30) NOT NULL COMMENT '批次号',
  `file_name` varchar(200) NOT NULL COMMENT '原始文件名',
  `file_hash` varchar(64) NOT NULL COMMENT '文件SHA-256，防重复导入',
  `total_rows` int NOT NULL DEFAULT '0' COMMENT '总行数',
  `success_rows` int NOT NULL DEFAULT '0' COMMENT '成功行数',
  `fail_rows` int NOT NULL DEFAULT '0' COMMENT '失败行数',
  `unclaimed_rows` int NOT NULL DEFAULT '0' COMMENT '未匹配到工号的行数',
  `status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '状态：PENDING待处理 PROCESSING处理中 SUCCESS成功 PARTIAL部分成功 FAILED失败',
  `error_file_path` varchar(300) DEFAULT NULL COMMENT '错误行回显文件路径',
  `import_by` bigint unsigned DEFAULT NULL COMMENT '导入人ID',
  `import_at` datetime(3) DEFAULT NULL COMMENT '导入时间',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_attendance_punch_import_batch_batch_no` (`batch_no`),
  UNIQUE KEY `uk_attendance_punch_import_batch_file_hash` (`file_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='打卡数据导入批次';


-- ---------------------------------------------------------------------
-- 10. device_user_relation 设备用户号与工号映射
-- 没有这张表，导入的打卡对不上人。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `device_user_relation` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `emp_no` varchar(20) NOT NULL COMMENT '工号',
  `device_user_no` varchar(30) NOT NULL COMMENT '设备用户号',
  `terminal_sn` varchar(50) NOT NULL DEFAULT '' COMMENT '限定设备SN；空串表示全局通用',
  `is_active` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否有效：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_device_user_relation_terminal_sn_device_user_no` (`terminal_sn`,`device_user_no`),
  KEY `idx_device_user_relation_emp_no` (`emp_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='设备用户号与工号映射';


-- ---------------------------------------------------------------------
-- 11. attendance_day_result 考勤日结果（核心表）
-- 每人每天一条。必须存 rule_version / calendar_version 快照，
-- 否则规则一改，历史结果无法解释。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `attendance_day_result` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `organization_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属组织快照；写入时取自 employment，保证历史归属不随调岗变化',
  `legal_entity_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属法人快照；写入时取自 employment.legal_entity_id',
  `work_date` date NOT NULL COMMENT '考勤日期',
  `shift_id` bigint unsigned DEFAULT NULL COMMENT '当日班次ID；休息日为 NULL',
  `rule_id` bigint unsigned DEFAULT NULL COMMENT '生效规则ID',
  `rule_version` int DEFAULT NULL COMMENT '规则版本快照',
  `calendar_version` int DEFAULT NULL COMMENT '工作日历版本快照',
  `day_type` varchar(20) NOT NULL COMMENT '当日法定属性：WORKDAY工作日 RESTDAY休息日 HOLIDAY法定节假日',
  `is_arranged` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否安排上班（含个人覆盖）：0否 1是',
  `is_required` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否应出勤：0否 1是；仅 WORKDAY+已安排 时为1',
  `required_minutes` int NOT NULL DEFAULT '0' COMMENT '应出勤分钟',
  `worked_minutes` int NOT NULL DEFAULT '0' COMMENT '实际在岗分钟',
  `late_minutes` int NOT NULL DEFAULT '0' COMMENT '迟到分钟',
  `early_minutes` int NOT NULL DEFAULT '0' COMMENT '早退分钟',
  `absent_minutes` int NOT NULL DEFAULT '0' COMMENT '缺勤分钟',
  `absent_type` varchar(20) DEFAULT NULL COMMENT '缺勤类型：NONE无 LATE迟到 EARLY早退 MISSING缺卡 ABSENT旷工',
  `missing_punch_count` tinyint NOT NULL DEFAULT '0' COMMENT '缺卡次数',
  `overtime_workday_minutes` int NOT NULL DEFAULT '0' COMMENT '工作日加班分钟（1.5倍）',
  `overtime_restday_minutes` int NOT NULL DEFAULT '0' COMMENT '休息日加班分钟（2倍）',
  `overtime_holiday_minutes` int NOT NULL DEFAULT '0' COMMENT '法定节假日加班分钟（3倍）',
  `leave_minutes` int NOT NULL DEFAULT '0' COMMENT '请假分钟',
  `status` varchar(20) NOT NULL DEFAULT 'NORMAL' COMMENT '当日状态：NORMAL正常 ABNORMAL异常 LEAVE请假 TRIP出差 REST休息 HOLIDAY法定假。旷工直接记 ABNORMAL，不设待定态',
  `calc_batch_no` varchar(30) DEFAULT NULL COMMENT '计算批次号，用于追溯重算',
  `is_locked` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否随月度结算锁定：0否 1是',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_attendance_day_result_organization_id` (`organization_id`),
  KEY `idx_attendance_day_result_legal_entity_id` (`legal_entity_id`),
  UNIQUE KEY `uk_attendance_day_result_employee_id_work_date` (`employee_id`,`work_date`),
  KEY `idx_attendance_day_result_work_date_is_locked` (`work_date`,`is_locked`),
  KEY `idx_attendance_day_result_calc_batch_no` (`calc_batch_no`),
  KEY `idx_attendance_day_result_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='考勤日结果';


-- ---------------------------------------------------------------------
-- 12. attendance_exception 考勤异常台账
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `attendance_exception` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `organization_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属组织快照；写入时取自 employment，保证历史归属不随调岗变化',
  `legal_entity_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属法人快照；写入时取自 employment.legal_entity_id',
  `work_date` date NOT NULL COMMENT '考勤日期',
  `exception_type` varchar(30) NOT NULL COMMENT '异常类型：LATE迟到 EARLY早退 MISSING_PUNCH缺卡 ABSENT旷工 OVERTIME_NO_APPLY未申请加班 OVERTIME_OVER_LIMIT加班超上限',
  `description` varchar(200) DEFAULT NULL COMMENT '异常描述',
  `handled_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '处理状态：PENDING待处理 HANDLED已处理 IGNORED已忽略',
  `handled_by` bigint unsigned DEFAULT NULL COMMENT '处理人ID',
  `handled_at` datetime(3) DEFAULT NULL COMMENT '处理时间',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_attendance_exception_organization_id` (`organization_id`),
  KEY `idx_attendance_exception_legal_entity_id` (`legal_entity_id`),
  KEY `idx_attendance_exception_employee_id_work_date` (`employee_id`,`work_date`),
  KEY `idx_attendance_exception_handled_status` (`handled_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='考勤异常台账';


-- ---------------------------------------------------------------------
-- 13. attendance_appeal 异常申诉与补卡
-- 补卡不写原始流水，写这里。原始流水保持只追加。
-- 补卡有月度次数上限（规则层 appeal_month_limit，默认3次/人/月）。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `attendance_appeal` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `organization_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属组织快照；写入时取自 employment，保证历史归属不随调岗变化',
  `legal_entity_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属法人快照；写入时取自 employment.legal_entity_id',
  `work_date` date NOT NULL COMMENT '考勤日期',
  `appeal_type` varchar(20) NOT NULL COMMENT '申诉类型：MISSING_PUNCH补卡（占用月度补卡额度） ABNORMAL异常说明（不占额度）',
  `appeal_time` datetime DEFAULT NULL COMMENT '补卡的打卡时间（appeal_type=MISSING_PUNCH 必填）；须填实际到岗时间，不得为消除迟到而提前',
  `punch_type` varchar(20) DEFAULT NULL COMMENT '补卡对应的打卡方式，枚举同 attendance_punch_raw.punch_type',
  `quota_month` varchar(7) DEFAULT NULL COMMENT '额度归属月份 yyyy-MM；用于统计月度补卡次数，仅 MISSING_PUNCH 填',
  `reason` varchar(500) NOT NULL COMMENT '申诉原因',
  `attach_path` varchar(300) DEFAULT NULL COMMENT '证明材料路径',
  `cc_user_ids` varchar(500) DEFAULT NULL COMMENT '抄送人ID，逗号分隔；审批流走完后抄送通知',
  `approval_instance_id` bigint unsigned DEFAULT NULL COMMENT '审批实例ID',
  `approval_status` varchar(20) NOT NULL DEFAULT 'DRAFT' COMMENT '审批状态：DRAFT草稿 SUBMITTED已提交 APPROVING审批中 APPROVED已通过 REJECTED已驳回 CANCELLED已撤销',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_attendance_appeal_organization_id` (`organization_id`),
  KEY `idx_attendance_appeal_legal_entity_id` (`legal_entity_id`),
  KEY `idx_attendance_appeal_employee_id_work_date` (`employee_id`,`work_date`),
  KEY `idx_attendance_appeal_employee_id_quota_month` (`employee_id`,`quota_month`),
  KEY `idx_attendance_appeal_approval_status` (`approval_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='考勤异常申诉与补卡';


-- ---------------------------------------------------------------------
-- 14. overtime_apply 加班单
-- 业务口径：**事后申请**（先加班，后填报）。审批通过后必须选择转化方式：
--   WAGE 转工资 / COMP_TIME 转调休（生成调休额度）。
-- 合规约束（劳动法第44条）：
--   工作日、法定节假日加班只能转工资，不能以调休替代；
--   休息日加班可优先调休。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `overtime_apply` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `order_no` varchar(30) NOT NULL COMMENT '单据号',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `organization_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属组织快照；写入时取自 employment，保证历史归属不随调岗变化',
  `legal_entity_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '所属法人快照；写入时取自 employment.legal_entity_id',
  `work_date` date NOT NULL COMMENT '加班所属日期（起始日）',
  `start_time` datetime NOT NULL COMMENT '加班开始时间',
  `end_time` datetime NOT NULL COMMENT '加班结束时间',
  `apply_hours` decimal(6,2) NOT NULL COMMENT '申请加班小时数（按最小单位取整后）',
  `confirm_hours` decimal(6,2) DEFAULT NULL COMMENT '认定加班小时数；审批后与实际打卡比对取小值',
  `overtime_kind` varchar(20) DEFAULT NULL COMMENT '加班档位：WORKDAY工作日 RESTDAY休息日 HOLIDAY法定节假日；跨档时为空，由引擎按自然日切分',
  `settle_type` varchar(20) DEFAULT NULL COMMENT '转化方式：WAGE转工资 COMP_TIME转调休。工作日/节假日档仅允许 WAGE',
  `settle_status` varchar(20) NOT NULL DEFAULT 'PENDING' COMMENT '转化状态：PENDING待转化 CONVERTED已转化 USED调休已休完 CANCELLED已撤销',
  `comp_time_hours` decimal(6,2) DEFAULT NULL COMMENT '折算调休小时数（settle_type=COMP_TIME 时填写）',
  `comp_time_expire_date` date DEFAULT NULL COMMENT '调休有效期截止日；过期作废',
  `converted_quota_id` bigint unsigned DEFAULT NULL COMMENT '转化后生成的调休额度流水ID（leave_quota_log.id）',
  `settled_at` datetime(3) DEFAULT NULL COMMENT '转化完成时间',
  `reason` varchar(500) NOT NULL COMMENT '加班事由',
  `approval_instance_id` bigint unsigned DEFAULT NULL COMMENT '审批实例ID',
  `approval_status` varchar(20) NOT NULL DEFAULT 'DRAFT' COMMENT '审批状态，枚举同 attendance_appeal.approval_status',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_overtime_apply_organization_id` (`organization_id`),
  KEY `idx_overtime_apply_legal_entity_id` (`legal_entity_id`),
  UNIQUE KEY `uk_overtime_apply_order_no` (`order_no`),
  KEY `idx_overtime_apply_employee_id_work_date` (`employee_id`,`work_date`),
  KEY `idx_overtime_apply_settle_status` (`settle_status`),
  CONSTRAINT `ck_overtime_apply_time` CHECK (`end_time` > `start_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='加班单（事后申请，可转工资或转调休）';


-- ---------------------------------------------------------------------
-- 15. attendance_month_close 月度结算锁
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `attendance_month_close` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `legal_entity_id` bigint unsigned NOT NULL COMMENT '法人ID',
  `close_month` varchar(7) NOT NULL COMMENT '结算月份，格式 yyyy-MM',
  `close_status` varchar(20) NOT NULL DEFAULT 'OPEN' COMMENT '状态：OPEN未结算 CLOSING结算中 CLOSED已结算',
  `close_by` bigint unsigned DEFAULT NULL COMMENT '结算人ID',
  `close_at` datetime(3) DEFAULT NULL COMMENT '结算时间',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_attendance_month_close_legal_entity_id_close_month` (`legal_entity_id`,`close_month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='考勤月度结算锁';


-- ---------------------------------------------------------------------
-- 16. attendance_adjust_order 考勤调整单
-- 仅用于已锁定月份的更正，必须审批。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `attendance_adjust_order` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `order_no` varchar(30) NOT NULL COMMENT '单据号',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `work_date` date NOT NULL COMMENT '考勤日期',
  `adjust_field` varchar(30) NOT NULL COMMENT '调整字段：LATE_MINUTES迟到 ABSENT_MINUTES缺勤 OVERTIME_MINUTES加班 LEAVE_MINUTES请假 STATUS状态',
  `before_value` varchar(100) DEFAULT NULL COMMENT '调整前值',
  `after_value` varchar(100) NOT NULL COMMENT '调整后值',
  `reason` varchar(500) NOT NULL COMMENT '调整原因',
  `approval_instance_id` bigint unsigned DEFAULT NULL COMMENT '审批实例ID',
  `approval_status` varchar(20) NOT NULL DEFAULT 'DRAFT' COMMENT '审批状态，枚举同 attendance_appeal.approval_status',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_attendance_adjust_order_order_no` (`order_no`),
  KEY `idx_attendance_adjust_order_employee_id_work_date` (`employee_id`,`work_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='考勤调整单';

SET FOREIGN_KEY_CHECKS = 1;
