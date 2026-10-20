-- =====================================================================
-- HR 人事管理系统 · 建表脚本 01：组织与职位
-- 数据库：rt-hrms    MySQL 8.0+    utf8mb4 / utf8mb4_general_ci
-- 依据：HR系统_数据库设计_V0.1.md 第四章
-- 表数：7
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- 1. legal_entity 法人主体
-- 13 个法人：集团 1 + 子公司 12。集团法人两个名称（主名 + 别名）。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `legal_entity` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `entity_code` varchar(20) NOT NULL COMMENT '法人编码，对应工号前缀：RT/AH/RM/GK/RX/GT/RD/RK/RG/RY/RL/TY/RJ',
  `entity_name` varchar(100) NOT NULL COMMENT '法人全称',
  `entity_alias` varchar(100) DEFAULT NULL COMMENT '法人别名；集团主体两个名称时，主名放 entity_name，另一个放这里',
  `credit_code` varchar(30) DEFAULT NULL COMMENT '统一社会信用代码',
  `legal_person` varchar(50) DEFAULT NULL COMMENT '法定代表人',
  `registered_address` varchar(200) DEFAULT NULL COMMENT '注册地址',
  `insurance_city_code` varchar(20) DEFAULT NULL COMMENT '主参保地城市编码，关联 social_insurance_plan.city_code',
  `is_group` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否集团主体：0否 1是（全库仅一条为 1）',
  `sort_no` int NOT NULL DEFAULT '0' COMMENT '排序号',
  `remark` varchar(500) DEFAULT NULL COMMENT '备注',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_legal_entity_entity_code` (`entity_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='法人主体';


-- ---------------------------------------------------------------------
-- 2. organization 组织节点
-- 集团 -> 法人 -> 中心 -> 部门 -> 组 -> 组，实测 6 级，结构按 10 级预留。
-- 只存"当前"形态；变更历史走 organization_history，
-- 员工历史归属走 employment 的日期区间。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `organization` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `org_code` varchar(30) NOT NULL COMMENT '组织编码，全局唯一',
  `org_name` varchar(100) NOT NULL COMMENT '组织名称',
  `legal_entity_id` bigint unsigned NOT NULL COMMENT '所属法人ID',
  `parent_id` bigint unsigned NOT NULL DEFAULT '0' COMMENT '上级组织ID；根节点为 0',
  `org_path` varchar(500) NOT NULL COMMENT '路径，形如 /1/3/15/；用于子树查询与数据权限前缀匹配',
  `org_level` tinyint unsigned NOT NULL DEFAULT '1' COMMENT '层级 1-10，实测用到 6',
  `org_type` varchar(20) NOT NULL COMMENT '组织类型：GROUP集团 COMPANY公司 CENTER中心 DEPARTMENT部门 TEAM班组 LINE产线',
  `is_production` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否生产单元：0否 1是；决定是否启用倒班排班与计件',
  `cost_center_code` varchar(30) DEFAULT NULL COMMENT '成本中心编码',
  `leader_employee_id` bigint unsigned DEFAULT NULL COMMENT '负责人员工ID；为空时由职位汇报关系反查',
  `status` varchar(20) NOT NULL DEFAULT 'ENABLED' COMMENT '状态：ENABLED启用 DISABLED停用',
  `effective_date` date NOT NULL COMMENT '生效日期',
  `source_doc_no` varchar(50) DEFAULT NULL COMMENT 'ISO受控文件编号，如 AT 4512.002.01O',
  `source_doc_version` varchar(10) DEFAULT NULL COMMENT 'ISO受控文件版本',
  `sort_no` int NOT NULL DEFAULT '0' COMMENT '同级排序号',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_organization_org_code` (`org_code`),
  KEY `idx_organization_parent_id` (`parent_id`),
  KEY `idx_organization_legal_entity_id` (`legal_entity_id`),
  KEY `idx_organization_org_path` (`org_path`(64))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='组织节点';


-- ---------------------------------------------------------------------
-- 3. organization_history 组织变更历史
-- 组织调整留痕：改名、调整上级、停用、合并、拆分。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `organization_history` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `organization_id` bigint unsigned NOT NULL COMMENT '组织ID',
  `change_type` varchar(20) NOT NULL COMMENT '变更类型：CREATE新建 UPDATE改名 MOVE调整上级 DISABLE停用 MERGE合并 SPLIT拆分',
  `before_data` json DEFAULT NULL COMMENT '变更前快照',
  `after_data` json DEFAULT NULL COMMENT '变更后快照',
  `effective_date` date NOT NULL COMMENT '生效日期',
  `change_order_no` varchar(30) DEFAULT NULL COMMENT '关联组织变更单号',
  `operator_id` bigint unsigned NOT NULL COMMENT '操作人ID',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_organization_history_organization_id` (`organization_id`,`effective_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='组织变更历史';


-- ---------------------------------------------------------------------
-- 4. position_grade 职级
-- 自定义 12 级（附录A初稿）。不硬编码，支持增删改；
-- 被引用的职级不能物理删除，只能停用。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `position_grade` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `grade_code` varchar(10) NOT NULL COMMENT '职级编码：L1-L12，可延展',
  `grade_name` varchar(50) NOT NULL COMMENT '职级名称，如「部门经理级」',
  `grade_level` tinyint unsigned NOT NULL COMMENT '级别数值，1为最高；用于比较与排序',
  `job_nature` varchar(20) NOT NULL COMMENT '岗位性质：FRONTLINE一线 BACKLINE二线',
  `grade_stage` varchar(20) NOT NULL COMMENT '职级阶段：DECISION决策管理 LEADER领导管理 MIDDLE中层管理 BASIC基层管理 EXECUTION执行',
  `grade_desc` varchar(200) DEFAULT NULL COMMENT '职级描述（定级判断依据）',
  `effective_date` date NOT NULL COMMENT '生效日期',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：0停用 1启用；停用后不可用于新定级，历史保留',
  `version_no` int NOT NULL DEFAULT '1' COMMENT '版本号，定义变更时 +1',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_position_grade_grade_code` (`grade_code`),
  KEY `idx_position_grade_grade_level` (`grade_level`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='职级';


-- ---------------------------------------------------------------------
-- 5. company_grade_relation 公司职级映射
-- 同一职级在不同法人的岗位名称不同（老数据：E2 在集团是副总经理、在子公司是总经理）。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `company_grade_relation` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `legal_entity_id` bigint unsigned NOT NULL COMMENT '法人ID',
  `grade_id` bigint unsigned NOT NULL COMMENT '职级ID',
  `position_name_in_company` varchar(50) DEFAULT NULL COMMENT '该法人下此职级的对外岗位名称',
  `remark` varchar(200) DEFAULT NULL COMMENT '备注',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_company_grade_relation_legal_entity_id_grade_id` (`legal_entity_id`,`grade_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='公司职级岗位名称映射';


-- ---------------------------------------------------------------------
-- 6. position 职位
-- 职位清单自定义重建。唯一性靠「组织 + 职位名称」，
-- 因为同名职位跨组织普遍存在（实测 20 个）。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `position` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `position_code` varchar(30) NOT NULL COMMENT '职位编码，全局唯一',
  `position_name` varchar(50) NOT NULL COMMENT '职位名称',
  `organization_id` bigint unsigned NOT NULL COMMENT '所属组织ID',
  `legal_entity_id` bigint unsigned NOT NULL COMMENT '所属法人ID（冗余，避免每次 join organization）',
  `grade_id` bigint unsigned NOT NULL COMMENT '所属职级ID',
  `parent_position_id` bigint unsigned DEFAULT NULL COMMENT '汇报上级职位ID；顶层为 NULL',
  `position_series` varchar(20) NOT NULL COMMENT '序列：MANAGE管理 TECH专业 OPERATE操作',
  `is_management` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否管理岗：0否 1是',
  `headcount` int DEFAULT NULL COMMENT '编制数；允许为空（老数据全为0，属从零建设）',
  `duty_desc` text COMMENT '职责说明（二期填充）',
  `status` varchar(20) NOT NULL DEFAULT 'ENABLED' COMMENT '状态：ENABLED启用 DISABLED停用',
  `effective_date` date NOT NULL COMMENT '生效日期',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_position_position_code` (`position_code`),
  UNIQUE KEY `uk_position_organization_id_position_name` (`organization_id`,`position_name`),
  KEY `idx_position_legal_entity_id` (`legal_entity_id`),
  KEY `idx_position_grade_id` (`grade_id`),
  KEY `idx_position_parent_position_id` (`parent_position_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='职位';


-- ---------------------------------------------------------------------
-- 7. employment 任职记录（核心表）
-- 「谁在什么时间、在哪个组织、担任什么职位」的唯一事实来源。
-- 考勤、薪酬、数据权限全部依赖它。
-- 业务约束（应用层保证）：同一员工同一时刻只能有一条
--   employment_type='PRIMARY' 且 is_current=1 的记录。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employment` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `employee_id` bigint unsigned NOT NULL COMMENT '员工ID',
  `position_id` bigint unsigned NOT NULL COMMENT '职位ID',
  `organization_id` bigint unsigned NOT NULL COMMENT '所在组织ID（冗余）',
  `legal_entity_id` bigint unsigned NOT NULL COMMENT '用工主体（工号所属法人），可与组织所属法人不同——对应跨法人派驻场景',
  `employment_type` varchar(20) NOT NULL DEFAULT 'PRIMARY' COMMENT '任职类型：PRIMARY主岗 CONCURRENT兼岗',
  `start_date` date NOT NULL COMMENT '开始日期',
  `end_date` date NOT NULL DEFAULT '9999-12-31' COMMENT '结束日期；在职为 9999-12-31',
  `change_type` varchar(20) NOT NULL COMMENT '异动类型：HIRE入职 REGULAR转正 TRANSFER调岗 PROMOTE晋升 SALARY_ADJUST调薪 DISPATCH借调 RESIGN离职 REHIRE返聘',
  `change_order_no` varchar(30) DEFAULT NULL COMMENT '关联异动单号',
  `is_current` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否当前记录：0历史 1当前；用于快速查在岗',
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否删除：0否 1是',
  `create_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  `update_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_employment_employee_id_start_date` (`employee_id`,`start_date`),
  KEY `idx_employment_organization_id` (`organization_id`),
  KEY `idx_employment_position_id` (`position_id`),
  KEY `idx_employment_is_current` (`is_current`),
  KEY `idx_employment_legal_entity_id` (`legal_entity_id`),
  CONSTRAINT `ck_employment_date` CHECK (`end_date` >= `start_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='任职记录';

SET FOREIGN_KEY_CHECKS = 1;
