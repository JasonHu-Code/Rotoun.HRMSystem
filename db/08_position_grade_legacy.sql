-- =====================================================================
-- 08_position_grade_legacy.sql  ·  用真实「职位级别清单」重建职级字典
-- ---------------------------------------------------------------------
-- 来源：2026-10-23 用户提供的现系统截图（组织管理 / 职位级别），
--       16 级（E0–E15）、4 个级别段，关联职位数合计 770。
--
-- 为什么要换掉 06 里的 L1–L12：那份是按附录 A 推的初稿（12 级、按"专业/技工"命名），
-- 与集团实际在用的 E 级体系对不上。职位编码规则本身就是 E{职级}{组织码}{序号}，
-- 职级沿用 E0–E15 才能和编码、历史数据、外部系统一一对应。
--
-- 执行顺序：00 → 01 → … → 07 → 本脚本
-- 幂等：可重复执行；旧 L 级仅在无引用时物理删除，有引用则停用保留。
-- 注意：数据与 06_init_data.sql 的职级段同源，06 为准，本脚本是存量库补丁。
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- 一、清理旧的 L1–L12 草稿
--     有 position 引用时不能删（外键语义），改为停用：停用后不可用于新定级，历史保留。
-- ---------------------------------------------------------------------
SET @l_ref := (
  SELECT COUNT(*) FROM `position` p
  JOIN `position_grade` g ON g.id = p.grade_id
  WHERE g.grade_code REGEXP '^L[0-9]+$' AND p.is_deleted = 0
);

DELETE FROM `position_grade`
WHERE `grade_code` REGEXP '^L[0-9]+$' AND @l_ref = 0;

UPDATE `position_grade` SET `is_enabled` = 0
WHERE `grade_code` REGEXP '^L[0-9]+$' AND @l_ref > 0;

-- ---------------------------------------------------------------------
-- 二、写入真实职级（16 级）
--     grade_level：1 为最高，E0 → 1 … E15 → 16
--     grade_stage：高层=LEADER（E0 为 DECISION）、中层=MIDDLE、普通管理=BASIC、一级员工=EXECUTION
--     grade_desc 里保留"原系统关联职位数"，等职位清单导入后可以直接对账
-- ---------------------------------------------------------------------
INSERT INTO `position_grade`
(`grade_code`, `grade_name`, `grade_level`, `job_nature`, `grade_stage`, `grade_desc`, `effective_date`, `is_enabled`)
VALUES
('E0',  '高层管理人员', 1,  'BACKLINE',  'DECISION',  '职级 E0｜原系统关联职位 3 个｜待确认：董事长/董事层', '2026-01-01', 1),
('E1',  '高层管理人员', 2,  'BACKLINE',  'LEADER',    '职级 E1｜原系统关联职位 3 个', '2026-01-01', 1),
('E2',  '高层管理人员', 3,  'BACKLINE',  'LEADER',    '职级 E2｜原系统关联职位 14 个', '2026-01-01', 1),
('E3',  '高层管理人员', 4,  'BACKLINE',  'LEADER',    '职级 E3｜原系统关联职位 26 个', '2026-01-01', 1),
('E4',  '中层管理人员', 5,  'BACKLINE',  'MIDDLE',    '职级 E4｜原系统关联职位 9 个', '2026-01-01', 1),
('E5',  '中层管理人员', 6,  'BACKLINE',  'MIDDLE',    '职级 E5｜原系统关联职位 87 个', '2026-01-01', 1),
('E6',  '中层管理人员', 7,  'BACKLINE',  'MIDDLE',    '职级 E6｜原系统关联职位 37 个', '2026-01-01', 1),
('E7',  '普通管理人员', 8,  'BACKLINE',  'BASIC',     '职级 E7｜原系统关联职位 103 个｜班长/组长层', '2026-01-01', 1),
('E8',  '一级员工',     9,  'FRONTLINE', 'EXECUTION', '职级 E8｜原系统关联职位 132 个', '2026-01-01', 1),
('E9',  '一级员工',     10, 'FRONTLINE', 'EXECUTION', '职级 E9｜原系统关联职位 143 个', '2026-01-01', 1),
('E10', '一级员工',     11, 'FRONTLINE', 'EXECUTION', '职级 E10｜原系统关联职位 132 个', '2026-01-01', 1),
('E11', '普通管理人员', 12, 'BACKLINE',  'BASIC',     '职级 E11｜原系统关联职位 17 个｜待确认：为何夹在员工级之间', '2026-01-01', 1),
('E12', '普通管理人员', 13, 'BACKLINE',  'BASIC',     '职级 E12｜原系统关联职位 12 个｜待确认：同上', '2026-01-01', 1),
('E13', '一级员工',     14, 'FRONTLINE', 'EXECUTION', '职级 E13｜原系统关联职位 14 个', '2026-01-01', 1),
('E14', '一级员工',     15, 'FRONTLINE', 'EXECUTION', '职级 E14｜原系统关联职位 20 个', '2026-01-01', 1),
('E15', '一级员工',     16, 'FRONTLINE', 'EXECUTION', '职级 E15｜原系统关联职位 18 个', '2026-01-01', 1)
ON DUPLICATE KEY UPDATE
  `grade_name`  = VALUES(`grade_name`),
  `grade_level` = VALUES(`grade_level`),
  `job_nature`  = VALUES(`job_nature`),
  `grade_stage` = VALUES(`grade_stage`),
  `grade_desc`  = VALUES(`grade_desc`),
  `is_enabled`  = VALUES(`is_enabled`);

-- ---------------------------------------------------------------------
-- 三、核对
-- ---------------------------------------------------------------------
-- 1) 应为 16 行，grade_level 1..16 连续无洞
-- SELECT grade_code, grade_name, grade_level, grade_stage, job_nature
-- FROM position_grade WHERE is_deleted = 0 ORDER BY grade_level;
--
-- 2) 级别段分布应与原系统一致
-- SELECT grade_name, COUNT(*) AS grade_cnt, SUM(job_nature = 'FRONTLINE') AS frontline_cnt
-- FROM position_grade WHERE is_deleted = 0 GROUP BY grade_name;
--
-- 3) 不应再有 L 级启用记录
-- SELECT COUNT(*) FROM position_grade WHERE grade_code LIKE 'L%' AND is_enabled = 1;
