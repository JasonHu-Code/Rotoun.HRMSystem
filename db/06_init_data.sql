-- =====================================================================
-- HR 人事管理系统 · 初始化数据脚本 06
-- 数据库：rt-hrms    MySQL 8.0+    utf8mb4 / utf8mb4_general_ci
-- 依据：HR系统_数据库设计_V0.1.md、《需求清单 V0.1.1》附录A
--
-- 内容：
--   1. 法人主体 13 条
--   2. 职级 12 条（附录A初稿，待 HR 评审后调整）
--   3. 默认考勤规则 1 条（集团级兜底）
--   4. 班次与时段（常白班、白班、夜班、两班倒）
--   5. 数据权限规则模板
--
-- 说明：字典项（性别/民族/学历等）请在 Rotoun 字典管理界面录入，
--       不在本脚本里写死 INSERT —— 避免与底座 sys_dict_* 的字段版本差异冲突。
--       需要的字典清单见文件末尾注释。
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 一、法人主体（13 个）
-- RT 为集团主体，两个名称：主名 + 别名。
-- RJ 浙江瑞镓的全称待补（参考资料只到「浙江瑞镓」）。
-- ---------------------------------------------------------------------
INSERT INTO `legal_entity`
(`entity_code`,`entity_name`,`entity_alias`,`is_group`,`sort_no`,`remark`)
VALUES
('RT','瑞堂塑料集团有限公司','浙江瑞堂塑料科技有限公司',1,1,'集团主体；两个名称指同一法人，勿建成两个法人'),
('AH','安徽瑞堂塑料科技有限公司',NULL,0,2,NULL),
('RY','宁波瑞铟新材料有限公司',NULL,0,3,NULL),
('RG','宁波瑞铬新材料有限公司',NULL,0,4,NULL),
('RL','宁波瑞铼粉末涂料有限公司',NULL,0,5,NULL),
('RM','宁波瑞镁自动化设备有限公司',NULL,0,6,NULL),
('RD','浙江瑞锝滚塑科技有限公司',NULL,0,7,NULL),
('RK','浙江瑞氪滚塑科技有限公司',NULL,0,8,NULL),
('RX','浙江瑞堂塑料销售有限公司',NULL,0,9,NULL),
('GK','广州瑞氪新材料有限公司',NULL,0,10,NULL),
('GT','广东瑞堂塑料科技有限公司',NULL,0,11,NULL),
('TY','宁波钛一文化传播有限公司',NULL,0,12,NULL),
('RJ','浙江瑞镓',NULL,0,13,'全称待补，参考资料只到简称')
ON DUPLICATE KEY UPDATE `entity_name` = VALUES(`entity_name`);


-- ---------------------------------------------------------------------
-- 二、职级（12 级，附录A初稿）
-- grade_level 1 为最高。job_nature: FRONTLINE一线 / BACKLINE二线
-- grade_stage: DECISION / LEADER / MIDDLE / BASIC / EXECUTION
-- ---------------------------------------------------------------------
INSERT INTO `position_grade`
(`grade_code`,`grade_name`,`grade_level`,`job_nature`,`grade_stage`,`grade_desc`,`effective_date`)
VALUES
('L1','董事长级',1,'BACKLINE','DECISION','决策管理层：董事会主席、董事','2026-01-01'),
('L2','总经理级',2,'BACKLINE','LEADER','领导管理层：集团总经理、子公司总经理','2026-01-01'),
('L3','副总经理级',3,'BACKLINE','LEADER','领导管理层：副总经理','2026-01-01'),
('L4','总监级',4,'BACKLINE','MIDDLE','中层管理层：中心主任、总监、副总监','2026-01-01'),
('L5','部门经理级',5,'BACKLINE','MIDDLE','中层管理层：部门经理','2026-01-01'),
('L6','主管级',6,'BACKLINE','BASIC','基层管理层：部门副经理、主管','2026-01-01'),
('L7','班组级',7,'FRONTLINE','BASIC','基层管理层：班长、组长、基层管理员','2026-01-01'),
('L8','高级专业级',8,'BACKLINE','EXECUTION','执行层：高级工程师、高级专员、高级会计','2026-01-01'),
('L9','中级专业级',9,'BACKLINE','EXECUTION','执行层：工程师、专员、会计、文员','2026-01-01'),
('L10','初级专业级',10,'BACKLINE','EXECUTION','执行层：助理工程师、助理、助理文员','2026-01-01'),
('L11','技工级',11,'FRONTLINE','EXECUTION','执行层：技工、机修工、检验员、叉车工','2026-01-01'),
('L12','普工与辅助级',12,'FRONTLINE','EXECUTION','执行层：普工、操作工、辅助工、清洁工、搬运工','2026-01-01')
ON DUPLICATE KEY UPDATE `grade_name` = VALUES(`grade_name`), `grade_desc` = VALUES(`grade_desc`);


-- ---------------------------------------------------------------------
-- 三、默认考勤规则（集团级兜底，必须有且仅有一条）
-- 数值按 2026-10-20 业务确认口径设置；
-- 各公司如需不同（如月加班上限），在公司级单独加一条 scope_type='COMPANY' 覆盖。
-- ---------------------------------------------------------------------
INSERT INTO `attendance_rule`
(`rule_name`,`scope_type`,`scope_id`,`rule_version`,`effective_from`,`effective_to`,
 `late_tolerance_min`,`early_tolerance_min`,`absent_threshold_min`,
 `overtime_need_apply`,`overtime_month_limit_hour`,`overtime_round_unit_min`,`overtime_round_type`,
 `workday_overtime_rate`,`restday_overtime_rate`,`holiday_overtime_rate`,
 `min_leave_unit`,`appeal_month_limit`,`appeal_window_days`,`allow_mobile_punch`,`is_enabled`,`remark`)
VALUES
('集团默认规则','GROUP',0,1,'2026-01-01','9999-12-31',
 0,0,240,
 1,36.00,60,'CEIL',
 1.5000,2.0000,3.0000,
 'HOUR',3,3,0,1,'基本无容差；加班事后申请，最小单位1小时；每月补卡3次')
ON DUPLICATE KEY UPDATE `rule_name` = VALUES(`rule_name`);


-- ---------------------------------------------------------------------
-- 四、班次与时段
-- 制造型公司用倒班；研发/销售/内容用常白班。
-- 夜班跨天，归属上班日。
-- ---------------------------------------------------------------------
INSERT INTO `shift`
(`shift_code`,`shift_name`,`legal_entity_id`,`is_cross_day`,`cross_day_rule`,
 `standard_work_hours`,`rest_minutes`,`punch_count`,`is_enabled`)
VALUES
('S_DAY_STD','常白班 08:30-17:30',NULL,0,'START_DAY',8.00,60,2,1),
('S_DAY_12','白班 08:00-20:00',NULL,0,'START_DAY',11.00,60,2,1),
('S_NIGHT','夜班 20:00-08:00',NULL,1,'START_DAY',11.00,60,2,1),
('S_OT_SHIFT','加班班次 18:00-21:00',NULL,0,'START_DAY',3.00,0,2,1)
ON DUPLICATE KEY UPDATE `shift_name` = VALUES(`shift_name`);

-- 常白班时段
INSERT INTO `shift_segment` (`shift_id`,`segment_no`,`work_start_time`,`work_end_time`,`is_cross_day`)
SELECT s.`id`, 1, '08:30:00', '17:30:00', 0 FROM `shift` s
WHERE s.`shift_code`='S_DAY_STD'
  AND NOT EXISTS (SELECT 1 FROM `shift_segment` g WHERE g.`shift_id`=s.`id` AND g.`segment_no`=1);

-- 白班时段
INSERT INTO `shift_segment` (`shift_id`,`segment_no`,`work_start_time`,`work_end_time`,`is_cross_day`)
SELECT s.`id`, 1, '08:00:00', '20:00:00', 0 FROM `shift` s
WHERE s.`shift_code`='S_DAY_12'
  AND NOT EXISTS (SELECT 1 FROM `shift_segment` g WHERE g.`shift_id`=s.`id` AND g.`segment_no`=1);

-- 夜班时段（跨天）
INSERT INTO `shift_segment` (`shift_id`,`segment_no`,`work_start_time`,`work_end_time`,`is_cross_day`)
SELECT s.`id`, 1, '20:00:00', '08:00:00', 1 FROM `shift` s
WHERE s.`shift_code`='S_NIGHT'
  AND NOT EXISTS (SELECT 1 FROM `shift_segment` g WHERE g.`shift_id`=s.`id` AND g.`segment_no`=1);

-- 加班班次时段
INSERT INTO `shift_segment` (`shift_id`,`segment_no`,`work_start_time`,`work_end_time`,`is_cross_day`)
SELECT s.`id`, 1, '18:00:00', '21:00:00', 0 FROM `shift` s
WHERE s.`shift_code`='S_OT_SHIFT'
  AND NOT EXISTS (SELECT 1 FROM `shift_segment` g WHERE g.`shift_id`=s.`id` AND g.`segment_no`=1);


-- ---------------------------------------------------------------------
-- 五、假期类型（含调休——加班转调休的落地载体）
-- is_statutory=1 表示法定假，0 表示公司假。
-- ---------------------------------------------------------------------
INSERT INTO `leave_type`
(`type_code`,`type_name`,`is_paid`,`is_statutory`,`min_unit`,`need_attachment_days`,`max_days_per_year`,`sort_no`,`is_enabled`)
VALUES
('ANNUAL','年假',1,1,'HOUR',NULL,NULL,1,1),
('COMP_TIME','调休',1,0,'HOUR',NULL,NULL,2,1),
('SICK','病假',1,1,'HOUR',2.0,NULL,3,1),
('PERSONAL','事假',0,0,'HOUR',NULL,NULL,4,1),
('MARRIAGE','婚假',1,1,'DAY',NULL,NULL,5,1),
('MATERNITY','产假',1,1,'DAY',NULL,NULL,6,1),
('PATERNITY','陪产假',1,1,'DAY',NULL,NULL,7,1),
('BEREAVEMENT','丧假',1,1,'DAY',NULL,NULL,8,1),
('WORK_INJURY','工伤假',1,1,'DAY',NULL,NULL,9,1)
ON DUPLICATE KEY UPDATE `type_name` = VALUES(`type_name`);


-- ---------------------------------------------------------------------
-- 六、数据权限规则模板（role_id 需替换为实际角色ID）
-- ---------------------------------------------------------------------
-- 集团 HR：全量可导出
-- INSERT INTO `data_scope_rule` (`role_id`,`scope_type`,`scope_value`,`can_export`,`remark`)
-- VALUES (@role_group_hr, 'ALL', NULL, 1, '集团人力资源部');
--
-- 公司 HR：只看本公司
-- INSERT INTO `data_scope_rule` (`role_id`,`scope_type`,`scope_value`,`can_export`,`remark`)
-- VALUES (@role_company_hr, 'COMPANY', @legal_entity_id, 0, '公司人力资源部');
--
-- 部门主管：看本部门及下级
-- INSERT INTO `data_scope_rule` (`role_id`,`scope_type`,`scope_value`,`can_export`,`remark`)
-- VALUES (@role_dept_leader, 'ORG_TREE', @org_id, 0, '部门主管');
--
-- 普通员工：只看自己
-- INSERT INTO `data_scope_rule` (`role_id`,`scope_type`,`scope_value`,`can_export`,`remark`)
-- VALUES (@role_employee, 'SELF', NULL, 0, '员工自助');


-- =====================================================================
-- 需要在 Rotoun「系统管理 → 字典管理」录入的字典类型清单
-- =====================================================================
-- 字典编码                 字典名称             取值示例
-- ---------------------------------------------------------------------
-- hr_gender              性别                 MALE男 / FEMALE女
-- hr_marital_status      婚姻状况              MARRIED / SINGLE / WIDOWED / DIVORCED
-- hr_health_status       健康状况              GOOD / NORMAL / DISABLED
-- hr_political_status    政治面貌              MASSES群众 / CPC中共党员 / LEAGUE共青团员 ...
-- hr_education_level     学历                  PRIMARY / JUNIOR / HIGH / SECONDARY / COLLEGE / BACHELOR / MASTER / DOCTOR
-- hr_degree              学位                  NONE / BACHELOR / MASTER / DOCTOR
-- hr_household_type      户口类型              RURAL_FAMILY / URBAN_FAMILY / RURAL_COLLECTIVE / URBAN_COLLECTIVE
-- hr_employment_nature   用工性质              CONTRACT / LABOR / REHIRE / INTERN
-- hr_employee_category   员工类别              FORMAL / INTERN / DISPATCH / EXPATRIATE / OTHER
-- hr_employee_status     员工状态              PENDING / PROBATION / ACTIVE / SUSPENDED / RESIGNING / RESIGNED / REHIRED
-- hr_position_series     职位序列              MANAGE / TECH / OPERATE
-- hr_org_type            组织类型              GROUP / COMPANY / CENTER / DEPARTMENT / TEAM / LINE
-- hr_contract_type       合同类型              FIXED / UNFIXED / TASK / LABOR / INTERN / REHIRE
-- hr_punch_type          打卡方式              FACE / FINGERPRINT / CARD / PASSWORD / MOBILE_GPS / MOBILE_WIFI / FIELD / REISSUE / FLEXIBLE
-- hr_resign_type         离职类型              ACTIVE / PASSIVE
-- hr_resign_reason       离职原因              按企业实际维护（老系统有31种，建议收敛到15种以内）
-- hr_cert_type           证照类型              SPECIAL_OPERATION / FORKLIFT / ELECTRIC / WELDING / OTHER
-- hr_insurance_city      参保城市              按实际参保城市维护（至少浙江/安徽/广东）
-- hr_attendance_status   考勤状态              NORMAL / ABNORMAL / LEAVE / TRIP / REST / HOLIDAY / NO_RECORD
-- hr_salary_item_type    薪资项目类型          INCOME / DEDUCTION / EMPLOYER_COST
-- =====================================================================
