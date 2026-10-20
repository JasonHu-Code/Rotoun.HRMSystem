-- =====================================================================
-- HR 人事管理系统 · 建表脚本 05：系统扩展
-- 数据库：rt-hrms    MySQL 8.0+    utf8mb4 / utf8mb4_general_ci
-- 依据：HR系统_数据库设计_V0.1.md 第十一章
-- 表数：5
--
-- 说明：登录、角色、菜单、字典、操作日志复用 RuoYi-Vue-Plus 现有表
--       （sys_user / sys_role / sys_menu / sys_dict_* / sys_oper_log），
--       本脚本只建业务侧扩展表。
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- 1. approval_flow 审批流模板
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `approval_flow` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `flow_code` varchar(30) NOT NULL COMMENT '流程编码',
  `flow_name` varchar(50) NOT NULL COMMENT '流程名称',
  `biz_type` varchar(30) NOT NULL COMMENT '业务类型：ONBOARD入职 REGULAR转正 RESIGN离职 TRANSFER调岗 SALARY_ADJUST调薪 LEAVE请假 OVERTIME加班 APPEAL申诉 ADJUST考勤调整 SHIFT_CHANGE改班 ORG_CHANGE组织变更',
  `condition_expr` varchar(500) DEFAULT NULL COMMENT '适用条件表达式，如 amount>5000 或 grade_level<=5；为空表示无条件',
  `legal_entity_id` bigint unsigned DEFAULT NULL COMMENT '限定法人；NULL 表示全集团',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：0否 1是',
  `remark` varchar(200) DEFAULT NULL COMMENT '备注',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_approval_flow_flow_code` (`flow_code`),
  KEY `idx_approval_flow_biz_type` (`biz_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='审批流模板';


-- ---------------------------------------------------------------------
-- 2. approval_flow_node 审批节点
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `approval_flow_node` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `flow_id` bigint unsigned NOT NULL COMMENT '流程ID',
  `node_no` tinyint NOT NULL COMMENT '节点序号，从1开始',
  `node_name` varchar(50) NOT NULL COMMENT '节点名称',
  `approver_type` varchar(20) NOT NULL COMMENT '审批人类型：ROLE按角色 USER指定人 LEADER直属上级 DEPT_LEADER部门负责人 HR人力资源',
  `approver_value` varchar(100) DEFAULT NULL COMMENT '审批人取值；approver_type=ROLE 时为角色编码，=USER 时为用户ID',
  `amount_min` decimal(14,2) DEFAULT NULL COMMENT '金额下限（金额分级审批用）',
  `amount_max` decimal(14,2) DEFAULT NULL COMMENT '金额上限',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_approval_flow_node_flow_id_node_no` (`flow_id`,`node_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='审批节点';


-- ---------------------------------------------------------------------
-- 3. approval_instance 审批实例
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `approval_instance` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `flow_id` bigint unsigned NOT NULL COMMENT '流程ID',
  `biz_type` varchar(30) NOT NULL COMMENT '业务类型，枚举同 approval_flow.biz_type',
  `biz_id` bigint unsigned NOT NULL COMMENT '业务单据ID',
  `biz_no` varchar(30) DEFAULT NULL COMMENT '业务单据号',
  `initiator_id` bigint unsigned NOT NULL COMMENT '发起人ID',
  `current_node_no` tinyint DEFAULT NULL COMMENT '当前节点序号',
  `status` varchar(20) NOT NULL DEFAULT 'APPROVING' COMMENT '状态：APPROVING审批中 APPROVED已通过 REJECTED已驳回 CANCELLED已撤销',
  `finished_at` datetime(3) DEFAULT NULL COMMENT '结束时间',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_approval_instance_biz_type_biz_id` (`biz_type`,`biz_id`),
  KEY `idx_approval_instance_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='审批实例';


-- ---------------------------------------------------------------------
-- 4. data_scope_rule 数据权限规则
-- 【禁止】在业务代码里写 if (role == 'ADMIN')，一律走本表。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `data_scope_rule` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `role_id` bigint unsigned NOT NULL COMMENT '角色ID（sys_role.role_id）',
  `scope_type` varchar(20) NOT NULL COMMENT '权限范围：ALL全量 COMPANY本公司 ORG_TREE组织及子树 ORG本组织 SELF仅本人',
  `scope_value` varchar(100) DEFAULT NULL COMMENT '范围取值；COMPANY=法人ID，ORG_TREE/ORG=组织ID，ALL/SELF 为空',
  `can_export` tinyint(1) NOT NULL DEFAULT '0' COMMENT '可见但不可导出时置 0：0不可导出 1可导出',
  `remark` varchar(200) DEFAULT NULL COMMENT '备注',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_data_scope_rule_role_id` (`role_id`),
  KEY `idx_data_scope_rule_scope_type_scope_value` (`scope_type`,`scope_value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='数据权限规则';


-- ---------------------------------------------------------------------
-- 5. biz_change_log 业务变更日志（敏感数据前后值）
-- 与 sys_oper_log 分工：sys_oper_log 记「谁做了什么操作」，
-- 本表记「哪个字段从什么变成了什么」。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `biz_change_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `table_name` varchar(50) NOT NULL COMMENT '表名',
  `biz_id` bigint unsigned NOT NULL COMMENT '业务主键ID',
  `biz_no` varchar(50) DEFAULT NULL COMMENT '业务编号，如工号、单据号',
  `field_name` varchar(50) NOT NULL COMMENT '字段名',
  `before_value` varchar(1000) DEFAULT NULL COMMENT '变更前值（敏感字段需脱敏）',
  `after_value` varchar(1000) DEFAULT NULL COMMENT '变更后值（敏感字段需脱敏）',
  `change_desc` varchar(200) DEFAULT NULL COMMENT '变更说明',
  `operator_id` bigint unsigned NOT NULL COMMENT '操作人ID',
  `operator_name` varchar(50) DEFAULT NULL COMMENT '操作人姓名（快照）',
  `operator_ip` varchar(50) DEFAULT NULL COMMENT '操作IP',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_biz_change_log_table_name_biz_id` (`table_name`,`biz_id`),
  KEY `idx_biz_change_log_create_at` (`create_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='业务变更日志';

SET FOREIGN_KEY_CHECKS = 1;
