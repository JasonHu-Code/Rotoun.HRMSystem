-- =====================================================================
-- 07_m0_datascope.sql  ·  M0 收尾：账号绑定完整性 + 组织数据权限规则
-- ---------------------------------------------------------------------
-- 执行顺序：00 → 01 → … → 06 → 本脚本
-- 幂等：可重复执行（索引/视图/角色/规则都做了存在性判断）
-- 依赖：00 底座（sys_role/sys_user_role/sys_user）、01 组织、02 员工
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- 一、employee.sys_user_id 唯一索引
--     一个账号只能绑定一个员工；允许多行为 NULL（未建账号的员工）。
--     MySQL 唯一索引对 NULL 不生效，正好满足这个语义。
-- ---------------------------------------------------------------------
SET @idx_exists := (
  SELECT COUNT(*) FROM information_schema.statistics
  WHERE table_schema = DATABASE()
    AND table_name = 'employee'
    AND index_name = 'uk_employee_sys_user_id'
);
SET @ddl := IF(@idx_exists = 0,
  'ALTER TABLE `employee` ADD UNIQUE KEY `uk_employee_sys_user_id` (`sys_user_id`)',
  'DO 0');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ---------------------------------------------------------------------
-- 二、sys_user.dept_id 降级为底座兼容字段
--     业务归属只认 employment.organization_id，这里只改注释不改类型。
-- ---------------------------------------------------------------------
ALTER TABLE `sys_user`
  MODIFY COLUMN `dept_id` bigint NULL DEFAULT NULL
  COMMENT '底座兼容字段，仅作展示；业务归属见 employment.organization_id';

-- ---------------------------------------------------------------------
-- 三、只读视图：账号 → 员工 → 主岗 → 组织
--     联表核对用，不参与业务查询（业务走 Mapper，避免视图成为隐形依赖）
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `v_user_org` AS
SELECT u.user_id,
       u.user_name,
       u.nick_name,
       e.id                AS employee_id,
       e.emp_no,
       em.organization_id,
       o.org_name,
       o.org_path,
       o.legal_entity_id,
       em.position_id,
       em.employment_type
FROM sys_user u
LEFT JOIN employee e
       ON e.sys_user_id = u.user_id AND e.is_deleted = 0
LEFT JOIN employment em
       ON em.employee_id = e.id
      AND em.is_current = 1
      AND em.employment_type = 'PRIMARY'
      AND em.is_deleted = 0
LEFT JOIN organization o
       ON o.id = em.organization_id AND o.is_deleted = 0;

-- ---------------------------------------------------------------------
-- 四、旧部门 → 新组织 映射表（一次性迁移用）
--     sys_dept.dept_id 与 organization.id 不是同一套 ID，迁移前必须人工核对。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mig_dept_org_map` (
  `id`          bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
  `old_dept_id` bigint unsigned NOT NULL COMMENT '旧 sys_dept.dept_id',
  `new_org_id`  bigint unsigned DEFAULT NULL COMMENT '新 organization.id；NULL 表示待确认',
  `remark`      varchar(200) DEFAULT NULL COMMENT '备注',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_mig_dept_org_map_old_dept_id` (`old_dept_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='旧部门→新组织映射（一次性迁移用）';


-- =====================================================================
-- 五、四类角色的数据权限规则初始化
-- ---------------------------------------------------------------------
-- 需要手工填两个变量：
--   @legal_entity_id  公司 HR 只看本公司时，填该法人 ID
--   @org_id           部门主管看本部门及子树时，填该组织 ID
-- 留 NULL 表示"尚未确定"，脚本会跳过这两条规则——不写规则等于看不到数据（默认拒绝），
-- 绝不会因为缺配置而变成全量可见。
-- =====================================================================
SET @legal_entity_id := NULL;
SET @org_id := NULL;

-- 5.1 角色（按 role_key 判重，已存在则不动）
--     新建角色的 data_scope 一律写 '0'（未设置）：这个底座字段本系统已废弃，
--     写 '1' 会让下面的迁移段把它当成旧角色再迁一条 ALL 出来。
--     底座的 sys_role.role_id 不是 AUTO_INCREMENT（脚手架用固定 ID 预置角色），
--     所以必须显式给主键：每次取 MAX+1，已存在的角色跳过插入。
SET @rid := (SELECT IFNULL(MAX(`role_id`), 0) + 1 FROM `sys_role`);
INSERT INTO `sys_role` (`role_id`, `tenant_id`, `role_name`, `role_key`, `role_sort`, `data_scope`,
                        `menu_check_strictly`, `dept_check_strictly`, `status`, `del_flag`,
                        `create_time`, `remark`)
SELECT @rid, '000000', '集团人力资源', 'hr_group', 10, '0', 1, 1, '0', '0', NOW(), '集团 HR：全量可见可导出'
WHERE NOT EXISTS (SELECT 1 FROM `sys_role` WHERE `role_key` = 'hr_group' AND `del_flag` = '0');

SET @rid := (SELECT IFNULL(MAX(`role_id`), 0) + 1 FROM `sys_role`);
INSERT INTO `sys_role` (`role_id`, `tenant_id`, `role_name`, `role_key`, `role_sort`, `data_scope`,
                        `menu_check_strictly`, `dept_check_strictly`, `status`, `del_flag`,
                        `create_time`, `remark`)
SELECT @rid, '000000', '公司人力资源', 'hr_company', 11, '0', 1, 1, '0', '0', NOW(), '公司 HR：只看本公司'
WHERE NOT EXISTS (SELECT 1 FROM `sys_role` WHERE `role_key` = 'hr_company' AND `del_flag` = '0');

SET @rid := (SELECT IFNULL(MAX(`role_id`), 0) + 1 FROM `sys_role`);
INSERT INTO `sys_role` (`role_id`, `tenant_id`, `role_name`, `role_key`, `role_sort`, `data_scope`,
                        `menu_check_strictly`, `dept_check_strictly`, `status`, `del_flag`,
                        `create_time`, `remark`)
SELECT @rid, '000000', '部门主管', 'hr_leader', 12, '0', 1, 1, '0', '0', NOW(), '主管：本部门及子树'
WHERE NOT EXISTS (SELECT 1 FROM `sys_role` WHERE `role_key` = 'hr_leader' AND `del_flag` = '0');

SET @rid := (SELECT IFNULL(MAX(`role_id`), 0) + 1 FROM `sys_role`);
INSERT INTO `sys_role` (`role_id`, `tenant_id`, `role_name`, `role_key`, `role_sort`, `data_scope`,
                        `menu_check_strictly`, `dept_check_strictly`, `status`, `del_flag`,
                        `create_time`, `remark`)
SELECT @rid, '000000', '普通员工', 'hr_employee', 13, '0', 1, 1, '0', '0', NOW(), '员工自助：只看自己'
WHERE NOT EXISTS (SELECT 1 FROM `sys_role` WHERE `role_key` = 'hr_employee' AND `del_flag` = '0');

-- 5.2 规则：一个角色一条，可重复执行
--     集团 HR = ALL（可导出）
INSERT INTO `data_scope_rule` (`role_id`, `scope_type`, `scope_value`, `can_export`, `remark`)
SELECT r.role_id, 'ALL', NULL, 1, '集团人力资源部'
FROM `sys_role` r
WHERE r.role_key = 'hr_group' AND r.del_flag = '0'
  AND NOT EXISTS (SELECT 1 FROM `data_scope_rule` d
                  WHERE d.role_id = r.role_id AND d.scope_type = 'ALL' AND d.is_deleted = 0);

--     公司 HR = COMPANY（不可导出）
INSERT INTO `data_scope_rule` (`role_id`, `scope_type`, `scope_value`, `can_export`, `remark`)
SELECT r.role_id, 'COMPANY', CAST(@legal_entity_id AS CHAR), 0, '公司人力资源部'
FROM `sys_role` r
WHERE r.role_key = 'hr_company' AND r.del_flag = '0'
  AND @legal_entity_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM `data_scope_rule` d
                  WHERE d.role_id = r.role_id AND d.is_deleted = 0);

--     部门主管 = ORG_TREE（不可导出）
INSERT INTO `data_scope_rule` (`role_id`, `scope_type`, `scope_value`, `can_export`, `remark`)
SELECT r.role_id, 'ORG_TREE', CAST(@org_id AS CHAR), 0, '部门主管'
FROM `sys_role` r
WHERE r.role_key = 'hr_leader' AND r.del_flag = '0'
  AND @org_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM `data_scope_rule` d
                  WHERE d.role_id = r.role_id AND d.is_deleted = 0);

--     普通员工 = SELF
INSERT INTO `data_scope_rule` (`role_id`, `scope_type`, `scope_value`, `can_export`, `remark`)
SELECT r.role_id, 'SELF', NULL, 0, '员工自助'
FROM `sys_role` r
WHERE r.role_key = 'hr_employee' AND r.del_flag = '0'
  AND NOT EXISTS (SELECT 1 FROM `data_scope_rule` d
                  WHERE d.role_id = r.role_id AND d.is_deleted = 0);


-- =====================================================================
-- 六、迁移：旧 sys_role.data_scope → data_scope_rule
-- ---------------------------------------------------------------------
-- 映射口径（M0 清单 4.2）：
--   1 全部数据      → ALL
--   2 自定义数据    → sys_role_dept 每条 → ORG
--   3 本部门        → ORG（取 sys_role_dept 第一条；无则待确认）
--   4 本部门及以下  → ORG_TREE（同上）
--   5 仅本人        → SELF
--   0 / 空          → 不生成（运行时 1=0）
-- 说明：旧 dept_id 必须经 mig_dept_org_map 换算成 organization.id，
--       未映射的一律不写规则，避免"看起来配好了、其实指向不存在的组织"。
-- =====================================================================

-- 6.1 全部数据 / 仅本人：不依赖组织，可直接迁
INSERT INTO `data_scope_rule` (`role_id`, `scope_type`, `scope_value`, `can_export`, `remark`)
SELECT r.role_id, 'ALL', NULL, 0, CONCAT('迁移自 sys_role.data_scope=1（', r.role_name, '）')
FROM `sys_role` r
WHERE r.del_flag = '0' AND r.data_scope = '1'
  AND NOT EXISTS (SELECT 1 FROM `data_scope_rule` d WHERE d.role_id = r.role_id AND d.is_deleted = 0);

INSERT INTO `data_scope_rule` (`role_id`, `scope_type`, `scope_value`, `can_export`, `remark`)
SELECT r.role_id, 'SELF', NULL, 0, CONCAT('迁移自 sys_role.data_scope=5（', r.role_name, '）')
FROM `sys_role` r
WHERE r.del_flag = '0' AND r.data_scope = '5'
  AND NOT EXISTS (SELECT 1 FROM `data_scope_rule` d WHERE d.role_id = r.role_id AND d.is_deleted = 0);

-- 6.2 自定义 / 本部门 / 本部门及以下：逐个旧部门换算，未映射的跳过（见 6.3 报告）
INSERT INTO `data_scope_rule` (`role_id`, `scope_type`, `scope_value`, `can_export`, `remark`)
SELECT DISTINCT r.role_id,
       CASE r.data_scope WHEN '4' THEN 'ORG_TREE' ELSE 'ORG' END,
       CAST(m.new_org_id AS CHAR),
       0,
       CONCAT('迁移自 sys_role.data_scope=', r.data_scope, '（', r.role_name, '）')
FROM `sys_role` r
JOIN `sys_role_dept` rd ON rd.role_id = r.role_id
JOIN `mig_dept_org_map` m ON m.old_dept_id = rd.dept_id AND m.new_org_id IS NOT NULL
WHERE r.del_flag = '0' AND r.data_scope IN ('2', '3', '4')
  AND NOT EXISTS (SELECT 1 FROM `data_scope_rule` d WHERE d.role_id = r.role_id AND d.is_deleted = 0);

-- 6.3 迁移报告（执行后单独跑，确认没有漏网角色）
-- SELECT r.role_id, r.role_name, r.data_scope,
--        (SELECT COUNT(*) FROM data_scope_rule d WHERE d.role_id = r.role_id AND d.is_deleted = 0) AS rule_cnt
-- FROM sys_role r
-- WHERE r.del_flag = '0' AND IFNULL(r.data_scope,'0') <> '0'
-- HAVING rule_cnt = 0;                      -- 应返回空；有结果说明该角色需要人工配规则
--
-- SELECT rd.role_id, rd.dept_id
-- FROM sys_role_dept rd
-- LEFT JOIN mig_dept_org_map m ON m.old_dept_id = rd.dept_id
-- WHERE m.id IS NULL OR m.new_org_id IS NULL;   -- 应返回空；有结果说明旧部门还没映射

SET FOREIGN_KEY_CHECKS = 1;


-- =====================================================================
-- 七、M0 验收前的数据校验（M0 清单 2.6）
-- =====================================================================
-- 1) 应为 0（除纯管理员）
-- SELECT COUNT(*) FROM employee e
--  WHERE e.is_deleted = 0 AND e.sys_user_id IS NULL;
--
-- 2) 应无结果：一个账号绑了多个员工
-- SELECT sys_user_id, COUNT(*) FROM employee
--  WHERE sys_user_id IS NOT NULL AND is_deleted = 0
--  GROUP BY sys_user_id HAVING COUNT(*) > 1;
--
-- 3) 应无结果：账号存在但没有当前主岗任职
-- SELECT u.user_id FROM sys_user u
--  LEFT JOIN employee e ON e.sys_user_id = u.user_id AND e.is_deleted = 0
--  LEFT JOIN employment em ON em.employee_id = e.id AND em.is_current = 1
--                         AND em.employment_type = 'PRIMARY' AND em.is_deleted = 0
--  WHERE u.del_flag = '0' AND em.id IS NULL;
--
-- 4) 规则配置一览（人工过一遍）
-- SELECT r.role_name, d.scope_type, d.scope_value, d.can_export
-- FROM data_scope_rule d JOIN sys_role r ON r.role_id = d.role_id
-- WHERE d.is_deleted = 0 ORDER BY r.role_sort;
