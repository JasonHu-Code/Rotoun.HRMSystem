# HR 人事管理系统 · 数据库设计 V0.1

> 编制日期：2026-10-19（2026-10-20 同步 DDL 与数据权限快照列）
> 输入：《HR人事管理系统_需求清单_V0.1.2》（241 条，v1.0 P0 80 条）
> 适用规范：《全流程统一开发规范 V1.1》第四章（数据库命名与设计规范）
> 目标库：MySQL 8.0，`rt-hrms`
> 状态：**已评审**。DDL 已落 6 个脚本，并在 MySQL 8.0.46 临时实例实测通过（含 8 张事务表的数据权限快照列）。

---

## 一、设计范围

本文档覆盖 **v1.0 的 P0 需求**，不覆盖 P1/P2。共 **59 张表**：

| 域 | 表数 | 覆盖需求 |
|---|---|---|
| A 组织与职位 | 7 | HR-ORG-01～05、07、11、12、18 |
| B 员工主数据 | 8 | HR-EMP-01～04、08、11～13、16、18、19 |
| C 入转调离 | 3 | HR-LCM-01～06、09 |
| D 劳动合同 | 3 | HR-CON-01～03 |
| E 考勤与排班 | 16 | HR-ATT-01～13、18～20、28、29 |
| F 假期 | 4 | HR-LEA-01～05 |
| G 薪酬 | 11 | HR-PAY-01～06、08～14 |
| H 社保 | 2 | HR-BEN-01、02 |
| I 系统扩展 | 5 | HR-SYS-01～05、08 |

---

## 二、全局约定

### 2.1 命名与类型

| 项 | 约定 |
|---|---|
| 表名/字段名 | 全小写 snake_case，单数实体名，禁驼峰、禁中文、禁歧义缩写 |
| 中间/关联表 | `a_b_relation` |
| 主键 | `id bigint unsigned auto_increment`，无业务含义 |
| 业务键 | 独立字段（`emp_no`、`org_code`、`position_code`），带唯一索引 |
| 布尔 | `is_xxx` / `has_xxx`，`tinyint(1)`，0/1 |
| 时间点 | `datetime(3)`；纯日期 `date`；纯时刻 `time` |
| 金额 | `decimal(14,2)`，禁 float/double |
| 比率 | `decimal(6,4)`（如 0.1500 表示 15%） |
| 时长 | 分钟用 `int`，小时用 `decimal(6,2)` |
| 枚举 | `varchar(20/30)` 存英文码，**不用 tinyint 数字**（可读性优先，且加值不用改注释） |
| 大文本 | `text` / `json` |
| 字符集 | `utf8mb4` / `utf8mb4_general_ci` |

### 2.2 通用强制字段（所有业务表必须有）

```sql
id          bigint unsigned not null auto_increment comment '主键',
is_deleted  tinyint(1)      not null default 0     comment '是否删除：0否 1是',
create_at   datetime(3)     not null default current_timestamp(3) comment '创建时间',
update_at   datetime(3)     not null default current_timestamp(3) on update current_timestamp(3) comment '更新时间',
primary key (id)
```

后续各表字段清单中**不再重复列出这四个字段**（个别表额外说明除外）。

### 2.3 删除策略

- **一律逻辑删除**（`is_deleted = 1`），物理删除只由 DBA 在归档期执行。
- 有历史依赖的表（`employment`、`attendance_day_result`、`salary_detail`）**禁止删除**，只能置失效状态。
- 被引用的主数据（职级、职位、班次）**不能删除，只能停用**（`status`/`is_enabled`），对应 `HR-ORG-18`。

### 2.4 索引命名

- 普通索引 `idx_表名_字段`，多字段用下划线连接：`idx_employment_employee_id_start_date`
- 唯一索引 `uk_表名_字段`
- 外键**不建物理外键约束**，只建索引（互联网项目惯例，避免级联锁与迁移困难），由应用层保证一致性。

### 2.5 方案表清单总览

```
A 组织与职位   legal_entity, organization, organization_history, position_grade,
              company_grade_relation, position, employment
B 员工主数据   employee, employee_education, employee_work_experience, employee_family,
              employee_bank_account, employee_certificate, employee_attachment, employee_change
C 入转调离     onboard_order, regular_order, resign_order
D 劳动合同     labor_contract, labor_contract_change, contract_renewal_remind
E 考勤与排班   attendance_rule, shift, shift_segment, employee_shift_binding, shift_schedule,
              work_calendar, work_calendar_override, attendance_punch_raw,
              attendance_punch_import_batch, device_user_relation, attendance_day_result,
              attendance_exception, attendance_appeal, overtime_apply,
              attendance_month_close, attendance_adjust_order
F 假期         leave_type, leave_quota, leave_quota_log, leave_apply
G 薪酬         salary_item, salary_plan, salary_plan_item, grade_salary_standard,
              social_insurance_plan, social_insurance_plan_item, salary_calc_batch,
              salary_detail, salary_detail_item, piece_rate, piece_output
H 社保         social_insurance_account, social_insurance_change
I 系统扩展     approval_flow, approval_flow_node, approval_instance, data_scope_rule, biz_change_log
```

---

## 三、底座复用说明（重要）

本系统复用 RuoYi-Vue-Plus 脚手架，**以下表已存在，本设计不重复建**：

| 已有表 | 用途 | 本系统如何使用 |
|---|---|---|
| `sys_user` | 登录账号 | `employee` 表加 `sys_user_id` 关联；不把员工信息塞进 sys_user |
| `sys_role` / `sys_role_menu` | 角色与功能权限 | 直接用 |
| `sys_menu` | 菜单与按钮权限 | 直接用 |
| `sys_dict_type` / `sys_dict_data` | 数据字典 | **直接用**，不另建字典表 |
| `sys_oper_log` | 操作日志 | 直接用；业务数据前后值另建 `biz_change_log` |
| `sys_login_log` | 登录日志 | 直接用 |
| `sys_dept` | 部门树 | **不使用**，见下 |

### 为什么不用 `sys_dept`

RuoYi 的 `sys_dept` 只有 `dept_id / parent_id / dept_name / order_num`。本系统组织需要：法人归属、6 级层级、节点类型（部门/班组/产线）、生效日期、受控文件编号。硬套 `sys_dept` 会把它改得面目全非，还会与 RuoYi 的数据权限体系互相牵制。

**结论**：新建 `organization` 作为唯一组织来源，`sys_dept` 保留但不写数据；**数据权限自己实现**（见第九章）。这是本设计里唯一需要偏离底座标准功能的地方，代价可控。

---

## 四、A 域 · 组织与职位

### 4.1 `legal_entity` 法人主体

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| entity_code | varchar(20) | 否 | | 法人编码，对应工号前缀：RT/AH/RM/GK/RX/GT/RD/RK/RG/RY/RL/TY/RJ |
| entity_name | varchar(100) | 否 | | 法人全称 |
| entity_alias | varchar(100) | 是 | null | 别名。集团主体两个名称：主名与别名各存一处 |
| credit_code | varchar(30) | 是 | null | 统一社会信用代码 |
| legal_person | varchar(50) | 是 | null | 法定代表人 |
| registered_address | varchar(200) | 是 | null | 注册地址 |
| insurance_city_code | varchar(20) | 是 | null | 主参保地城市编码，关联社保方案 |
| is_group | tinyint(1) | 否 | 0 | 是否集团主体：0否 1是（全库仅一条为 1） |
| sort_no | int | 否 | 0 | 排序 |

索引：`uk_legal_entity_entity_code(entity_code)`

### 4.2 `organization` 组织节点

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| org_code | varchar(30) | 否 | | 组织编码，全局唯一 |
| org_name | varchar(100) | 否 | | 组织名称 |
| legal_entity_id | bigint | 否 | | 所属法人 |
| parent_id | bigint | 否 | 0 | 上级组织，根节点为 0 |
| org_path | varchar(500) | 否 | | 路径 `/1/3/15/`，用于子树查询与数据权限 |
| org_level | tinyint | 否 | 1 | 层级 1–10，实测用到 6 |
| org_type | varchar(20) | 否 | | GROUP集团 / COMPANY公司 / CENTER中心 / DEPARTMENT部门 / TEAM班组 / LINE产线 |
| is_production | tinyint(1) | 否 | 0 | 是否生产单元：0否 1是。决定是否启用倒班排班 |
| cost_center_code | varchar(30) | 是 | null | 成本中心编码 |
| leader_employee_id | bigint | 是 | null | 负责人；为空时由职位汇报关系反查 |
| status | varchar(20) | 否 | 'ENABLED' | ENABLED启用 / DISABLED停用 |
| effective_date | date | 否 | | 生效日期 |
| source_doc_no | varchar(50) | 是 | null | 受控文件编号，如 `AT 4512.002.01O` |
| source_doc_version | varchar(10) | 是 | null | 受控文件版本 |
| sort_no | int | 否 | 0 | 同级排序 |

索引：
- `uk_organization_org_code(org_code)`
- `idx_organization_parent_id(parent_id)`
- `idx_organization_legal_entity_id(legal_entity_id)`
- `idx_organization_org_path(org_path(64))`

### 4.3 `organization_history` 组织变更历史

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| organization_id | bigint | 否 | | 组织 ID |
| change_type | varchar(20) | 否 | | CREATE新建 / UPDATE改名 / MOVE调整上级 / DISABLE停用 / MERGE合并 / SPLIT拆分 |
| before_data | json | 是 | null | 变更前快照 |
| after_data | json | 是 | null | 变更后快照 |
| effective_date | date | 否 | | 生效日期 |
| change_order_no | varchar(30) | 是 | null | 关联组织变更单号 |
| operator_id | bigint | 否 | | 操作人 |

索引：`idx_organization_history_organization_id(organization_id, effective_date)`

### 4.4 `position_grade` 职级

按 12 级初稿落地，**不硬编码**，支持增删改（`HR-ORG-18`）。

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| grade_code | varchar(10) | 否 | | 职级编码：L1–L12，新增可延展 L13… |
| grade_name | varchar(50) | 否 | | 职级名称，如「部门经理级」 |
| grade_level | tinyint | 否 | | 数值级别，**1 最高**。用于比较大小与排序 |
| job_nature | varchar(20) | 否 | | 岗位性质：FRONTLINE一线 / BACKLINE二线 |
| grade_stage | varchar(20) | 否 | | 职级阶段：DECISION决策管理 / LEADER领导管理 / MIDDLE中层管理 / BASIC基层管理 / EXECUTION执行 |
| grade_desc | varchar(200) | 是 | null | 职级描述（定级判断依据） |
| effective_date | date | 否 | | 生效日期 |
| is_enabled | tinyint(1) | 否 | 1 | 是否启用：0停用 1启用。**停用后不可用于新定级，历史保留** |
| version_no | int | 否 | 1 | 版本号，每次定义变更 +1 |

索引：
- `uk_position_grade_grade_code(grade_code)`
- `idx_position_grade_grade_level(grade_level)`

### 4.5 `company_grade_relation` 公司职级映射

同一职级在不同法人的岗位名称不同（老数据：E2 在集团是副总经理、在子公司是总经理）。

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| legal_entity_id | bigint | 否 | | 法人 |
| grade_id | bigint | 否 | | 职级 |
| position_name_in_company | varchar(50) | 是 | null | 该法人下此职级的对外岗位名称 |
| remark | varchar(200) | 是 | null | 备注 |

索引：`uk_company_grade_relation_legal_entity_id_grade_id(legal_entity_id, grade_id)`

### 4.6 `position` 职位

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| position_code | varchar(30) | 否 | | 职位编码，全局唯一 |
| position_name | varchar(50) | 否 | | 职位名称。**唯一性靠"组织 + 名称"**，因为同名职位跨组织存在（实测 20 个） |
| organization_id | bigint | 否 | | 所属组织 |
| legal_entity_id | bigint | 否 | | 所属法人（冗余，避免每次 join organization） |
| grade_id | bigint | 否 | | 所属职级 |
| parent_position_id | bigint | 是 | null | 汇报上级职位；顶层为 null |
| position_series | varchar(20) | 否 | | 序列：MANAGE管理 / TECH专业 / OPERATE操作 |
| is_management | tinyint(1) | 否 | 0 | 是否管理岗 |
| headcount | int | 是 | null | 编制数；**允许为空**（实测老数据全为 0，属从零建设） |
| duty_desc | text | 是 | null | 职责说明（二期） |
| status | varchar(20) | 否 | 'ENABLED' | ENABLED启用 / DISABLED停用 |
| effective_date | date | 否 | | 生效日期 |

索引：
- `uk_position_position_code(position_code)`
- `uk_position_organization_id_position_name(organization_id, position_name)`
- `idx_position_grade_id(grade_id)`
- `idx_position_parent_position_id(parent_position_id)`

### 4.7 `employment` 任职记录（核心表）

这是「谁在什么时间、在哪个组织、担任什么职位」的唯一事实来源。考勤、薪酬、数据权限全部依赖它。

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| employee_id | bigint | 否 | | 员工 |
| position_id | bigint | 否 | | 职位 |
| organization_id | bigint | 否 | | 所在组织（冗余） |
| legal_entity_id | bigint | 否 | | **用工主体**（工号所属法人），可与 organization 所属法人不同——对应 73 人跨法人场景 |
| employment_type | varchar(20) | 否 | 'PRIMARY' | PRIMARY主岗 / CONCURRENT兼岗 |
| start_date | date | 否 | | 开始日期 |
| end_date | date | 否 | '9999-12-31' | 结束日期，在职为 9999-12-31 |
| change_type | varchar(20) | 否 | | 异动类型：HIRE入职 / REGULAR转正 / TRANSFER调岗 / PROMOTE晋升 / SALARY_ADJUST调薪 / DISPATCH借调 / RESIGN离职 / REHIRE返聘 |
| change_order_no | varchar(30) | 是 | null | 关联异动单号 |
| is_current | tinyint(1) | 否 | 1 | 是否当前记录：0历史 1当前。**用于快速查在岗** |

索引：
- `idx_employment_employee_id_start_date(employee_id, start_date)`
- `idx_employment_organization_id(organization_id)`
- `idx_employment_position_id(position_id)`
- `idx_employment_is_current(is_current)`

**业务约束（应用层保证）**：同一员工同一时刻只能有一条 `employment_type='PRIMARY'` 且 `is_current=1` 的记录。

---

## 五、B 域 · 员工主数据

### 5.1 `employee` 员工主数据

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| emp_no | varchar(20) | 否 | | 工号。规则 `{公司码2位}{入司年2位}{序号6位}`，**不可变**，调动不改 |
| emp_name | varchar(50) | 否 | | 姓名 |
| used_name | varchar(50) | 是 | null | 曾用名 |
| id_card_cipher | varchar(200) | 是 | null | 身份证号密文（AES-256） |
| id_card_hash | varchar(64) | 是 | null | 身份证号 SHA-256，**用于唯一性校验**（密文无法直接唯一） |
| id_card_mask | varchar(30) | 是 | null | 脱敏展示值，如 `513***273X` |
| gender | varchar(10) | 是 | null | MALE男 / FEMALE女 |
| birthday | date | 是 | null | 出生日期，可由身份证解析 |
| nation_code | varchar(10) | 是 | null | 民族编码，关联字典 |
| native_place_code | varchar(20) | 是 | null | 籍贯编码（老系统用 3486 条码表） |
| nationality_code | varchar(10) | 是 | '01' | 国籍编码 |
| political_status | varchar(20) | 是 | null | 政治面貌编码 |
| marital_status | varchar(20) | 是 | null | 婚姻状况：MARRIED已婚 / SINGLE未婚 / WIDOWED丧偶 / DIVORCED离异。**新系统用英文码，不用老系统的 YH/WH/SO/LY** |
| health_status | varchar(20) | 是 | null | 健康状况：GOOD良好 / NORMAL一般 / DISABLED残疾 |
| mobile_cipher | varchar(200) | 是 | null | 手机号密文 |
| mobile_mask | varchar(20) | 是 | null | 手机号脱敏值 |
| address | varchar(200) | 是 | null | 现住址 |
| household_address | varchar(200) | 是 | null | 户口所在地 |
| household_type | varchar(20) | 是 | null | 户口类型：RURAL_FAMILY农村家庭户 / URBAN_FAMILY城镇家庭户 / RURAL_COLLECTIVE / URBAN_COLLECTIVE |
| emergency_contact | varchar(50) | 是 | null | 紧急联系人 |
| emergency_mobile_cipher | varchar(200) | 是 | null | 紧急联系人电话密文 |
| education_level | varchar(20) | 是 | null | 最高学历：PRIMARY小学 / JUNIOR初中 / HIGH高中 / SECONDARY中专 / COLLEGE大专 / BACHELOR本科 / MASTER硕士 / DOCTOR博士。**"专科"归入 COLLEGE，不单独设值** |
| degree | varchar(20) | 是 | null | 学位：NONE无 / BACHELOR学士 / MASTER硕士 / DOCTOR博士 |
| title | varchar(30) | 是 | null | 职称，字典值 |
| work_area_code | varchar(20) | 是 | null | 工作地区（浙江/安徽/广东…） |
| first_work_date | date | 是 | null | 参加工作日期，用于算社会工龄（年假天数依据） |
| entry_date | date | 否 | | 入职日期，用于算司龄 |
| employee_status | varchar(20) | 否 | 'PENDING' | PENDING待入职 / PROBATION试用 / ACTIVE在职 / SUSPENDED停薪留职 / RESIGNING待离职 / RESIGNED已离职 / REHIRED返聘 |
| employment_nature | varchar(20) | 否 | 'CONTRACT' | 用工性质：CONTRACT合同工 / LABOR劳务工 / REHIRE退休返聘 / INTERN实习生 |
| employee_category | varchar(20) | 是 | null | 员工类别：FORMAL正式 / INTERN实习 / DISPATCH服务派遣 / EXPATRIATE外派 / OTHER其他 |
| current_employment_id | bigint | 是 | null | 当前主任职记录 ID，便于免 join 查询 |
| sys_user_id | bigint | 是 | null | 关联登录账号 |
| avatar_path | varchar(300) | 是 | null | 照片路径（**不存二进制**） |

索引：
- `uk_employee_emp_no(emp_no)`
- `uk_employee_id_card_hash(id_card_hash)`
- `idx_employee_emp_name(emp_name)`
- `idx_employee_employee_status(employee_status)`
- `idx_employee_current_employment_id(current_employment_id)`

### 5.2 员工子表

四张子表结构相近，仅列各自特有字段，其余均为「employee_id + 业务字段 + 通用字段」。

| 表 | 关键字段 | 说明 |
|---|---|---|
| `employee_education` | school_name, major, education_level, degree, start_date, end_date, is_highest | 多段学历。`is_highest` 标记最高学历 |
| `employee_work_experience` | company_name, position_name, start_date, end_date, leave_reason | 入职前经历 |
| `employee_family` | member_name, relation, birthday, work_unit, mobile_cipher | 家庭成员 |
| `employee_bank_account` | bank_name, branch_name, account_cipher, account_mask, account_hash, is_primary | 工资账户。**卡号加密 + 脱敏 + 哈希去重** |
| `employee_certificate` | cert_type, cert_no, issue_date, expire_date, cert_file_path | 证照。`expire_date` 支持到期预警（`HR-EMP-09`） |
| `employee_attachment` | attach_type, file_name, file_path, file_size, file_hash | 档案附件。**文件存对象存储/文件服务器，库里只存路径** |

### 5.3 `employee_change` 员工异动流水

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| employee_id | bigint | 否 | | 员工 |
| change_type | varchar(20) | 否 | | 异动类型，同 `employment.change_type` |
| effective_date | date | 否 | | 生效日期 |
| before_data | json | 是 | null | 变更前（组织/职位/职级/薪档/汇报人） |
| after_data | json | 是 | null | 变更后 |
| change_order_no | varchar(30) | 是 | null | 异动单号 |
| operator_id | bigint | 否 | | 操作人 |

索引：`idx_employee_change_employee_id_effective_date(employee_id, effective_date)`

---

## 六、C 域 · 入转调离

三张单据表。结构一致：单据头 + 审批状态 + 生效后触发的动作。

| 表 | 关键字段 | 生效后动作 |
|---|---|---|
| `onboard_order` | order_no, employee_id, entry_date, organization_id, position_id, grade_id, employment_nature, contract_type, probation_months, approval_instance_id | 生成 employee + employment + 合同 + 社保参保 |
| `regular_order` | order_no, employee_id, probation_end_date, assess_result, regular_date, approval_instance_id | 改 employee_status、写 employment（REGULAR） |
| `resign_order` | order_no, employee_id, resign_type(ACTIVE主动/PASSIVE被动), resign_reason_code, last_work_date, handover_status, approval_instance_id | 改 employee_status、关 employment（end_date）、停社保、停账号 |

共同字段：`approval_status`（DRAFT/SUBMITTED/APPROVING/APPROVED/REJECTED/CANCELLED）。

---

## 七、D 域 · 劳动合同

### 7.1 `labor_contract`

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| employee_id | bigint | 否 | | 员工 |
| contract_no | varchar(50) | 是 | null | 合同编号 |
| contract_type | varchar(20) | 否 | | FIXED固定期限 / UNFIXED无固定期限 / TASK以完成一定工作为期限 / LABOR劳务 / INTERN实习 / REHIRE返聘 |
| sign_date | date | 否 | | 签订日期 |
| start_date | date | 否 | | 合同开始日 |
| end_date | date | 是 | null | 合同结束日；无固定期限为 null |
| probation_start_date | date | 是 | null | 试用期开始 |
| probation_end_date | date | 是 | null | 试用期结束 |
| renew_count | tinyint | 否 | 0 | 第几次续签，0 为初签。**连续两次后应提示无固定期限** |
| parent_contract_id | bigint | 是 | null | 上一份合同 ID |
| status | varchar(20) | 否 | 'ACTIVE' | ACTIVE生效 / EXPIRED到期 / TERMINATED解除 / CANCELLED作废 |
| file_path | varchar(300) | 是 | null | 合同扫描件路径 |

索引：`idx_labor_contract_employee_id(employee_id)`、`idx_labor_contract_end_date(end_date)`

### 7.2 另两张

| 表 | 用途 |
|---|---|
| `labor_contract_change` | 合同变更（岗位、薪资、期限变更协议），字段：contract_id, change_type, change_content, effective_date, file_path |
| `contract_renewal_remind` | 到期预警任务，字段：contract_id, remind_date, remind_level(30/60/90), is_sent |

---

## 八、E 域 · 考勤与排班

这是全库最复杂的域。设计要点先说清：

> **原始流水只追加、日结果是算出来的、规则与班次必须留快照。** 这三条决定了表结构。

### 8.1 `attendance_rule` 考勤规则（分层配置）

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| rule_name | varchar(50) | 否 | | 规则名称 |
| scope_type | varchar(20) | 否 | | GROUP集团 / COMPANY公司 / DEPARTMENT部门 / TEAM班组 / EMPLOYEE个人 |
| scope_id | bigint | 否 | | 对应层级 ID。`scope_type=GROUP` 时固定为 0 |
| rule_version | int | 否 | 1 | 版本号 |
| effective_from | date | 否 | | 生效起 |
| effective_to | date | 否 | '9999-12-31' | 生效止 |
| late_tolerance_min | int | 否 | 5 | 迟到容差（分钟） |
| early_tolerance_min | int | 否 | 5 | 早退容差（分钟） |
| absent_threshold_min | int | 否 | 240 | 旷工判定阈值（超过则计旷工） |
| overtime_need_apply | tinyint(1) | 否 | 1 | 加班是否需事前申请 |
| overtime_month_limit_hour | decimal(6,2) | 是 | 36.00 | 月加班上限（小时），超限预警不硬拦 |
| workday_overtime_rate | decimal(6,4) | 否 | 1.5000 | 工作日加班倍率 |
| restday_overtime_rate | decimal(6,4) | 否 | 2.0000 | 休息日加班倍率 |
| holiday_overtime_rate | decimal(6,4) | 否 | 3.0000 | 法定节假日加班倍率 |
| min_leave_unit | varchar(20) | 否 | 'HOUR' | 请假最小单位：HOUR小时 / HALF_DAY半天 / DAY天 |
| allow_mobile_punch | tinyint(1) | 否 | 0 | 是否允许手机打卡 |
| is_enabled | tinyint(1) | 否 | 1 | 是否启用 |

索引：`idx_attendance_rule_scope(scope_type, scope_id, effective_from)`

**继承链解析规则**（对应 `HR-ATT-19`）：按 `EMPLOYEE → TEAM → DEPARTMENT → COMPANY → GROUP` 顺序查找，取第一个在生效区间内且 `is_enabled=1` 的规则。解析结果与版本写入 `attendance_day_result`。

### 8.2 `shift` 班次模板

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| shift_code | varchar(30) | 否 | | 班次编码 |
| shift_name | varchar(50) | 否 | | 班次名称，如「白班 08:00-20:00」 |
| legal_entity_id | bigint | 是 | null | 所属法人；null 表示集团通用 |
| is_cross_day | tinyint(1) | 否 | 0 | 是否跨天（夜班） |
| cross_day_rule | varchar(20) | 否 | 'START_DAY' | 跨天归属：START_DAY归上班日 / END_DAY归下班日。**默认归上班日** |
| standard_work_hours | decimal(6,2) | 否 | 8.00 | 标准工时 |
| rest_minutes | int | 否 | 60 | 班内休息时长 |
| punch_count | tinyint | 否 | 2 | 应打卡次数 |
| late_tolerance_min | int | 是 | null | 覆盖规则层容差；null 表示继承 |
| is_flexible | tinyint(1) | 否 | 0 | 是否弹性班（核心时段 + 弹性区间） |
| flexible_core_start | time | 是 | null | 弹性核心时段开始 |
| flexible_core_end | time | 是 | null | 弹性核心时段结束 |
| is_enabled | tinyint(1) | 否 | 1 | 是否启用 |

索引：`uk_shift_shift_code(shift_code)`

### 8.3 `shift_segment` 班次时段（多段班）

一段班一个时段；两段班（上午/下午）就是两条记录。

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| shift_id | bigint | 否 | | 班次 |
| segment_no | tinyint | 否 | | 段序号，从 1 开始 |
| work_start_time | time | 否 | | 上班时刻 |
| work_end_time | time | 否 | | 下班时刻 |
| is_cross_day | tinyint(1) | 否 | 0 | 本段是否跨天 |

索引：`uk_shift_segment_shift_id_segment_no(shift_id, segment_no)`

### 8.4 `employee_shift_binding` 个人长期班次（长期特殊工时）

对应 `HR-ATT-20`。**个人时段差异走这张表，不给个人复制规则。**

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| employee_id | bigint | 否 | | 员工 |
| shift_id | bigint | 否 | | 绑定的班次 |
| reason_type | varchar(30) | 否 | | 原因：LACTATION哺乳期 / PREGNANT孕期 / INJURY工伤 / DISABILITY残疾 / STATIONED驻外 / DUTY值班岗 / OTHER其他。**不提供"自由填写"** |
| reason_desc | varchar(200) | 是 | null | 原因补充说明 |
| start_date | date | 否 | | 生效起 |
| end_date | date | 是 | null | 生效止；null 表示长期 |
| approval_instance_id | bigint | 是 | null | 审批实例，**必须审批** |

索引：`idx_employee_shift_binding_employee_id_start_date(employee_id, start_date)`

### 8.5 `shift_schedule` 排班表

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| employee_id | bigint | 否 | | 员工 |
| work_date | date | 否 | | 排班日期 |
| shift_id | bigint | 否 | | 班次 |
| schedule_type | varchar(20) | 否 | 'ROTATION' | ROTATION轮班生成 / MANUAL手工 / CHANGE改班 |
| change_order_no | varchar(30) | 是 | null | 改班单号 |
| is_rest | tinyint(1) | 否 | 0 | 是否休息日（排了空白班） |

索引：`uk_shift_schedule_employee_id_work_date(employee_id, work_date)`、`idx_shift_schedule_work_date(work_date)`

### 8.6 `work_calendar` 工作日历（公司级，法定属性）

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| legal_entity_id | bigint | 否 | | 法人；不同厂区可不同 |
| calendar_date | date | 否 | | 日期 |
| day_type | varchar(20) | 否 | | WORKDAY工作日 / RESTDAY休息日 / HOLIDAY法定节假日 |
| holiday_name | varchar(50) | 是 | null | 节假日名称 |
| calendar_version | int | 否 | 1 | 日历版本 |

索引：`uk_work_calendar_legal_entity_id_calendar_date_version(legal_entity_id, calendar_date, calendar_version)`

### 8.7 `work_calendar_override` 个人日历覆盖

**只能把休息日/节假日改成"安排上班"，不能改法定属性。** 这是加班费合规的关键（`HR-ATT-04`）。

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| employee_id | bigint | 否 | | 员工 |
| calendar_date | date | 否 | | 日期 |
| arrange_work | tinyint(1) | 否 | 1 | 是否安排上班：1是 0否 |
| reason | varchar(200) | 是 | null | 原因（必填，用于事后举证） |
| order_no | varchar(30) | 是 | null | 关联单据 |

索引：`uk_work_calendar_override_employee_id_calendar_date(employee_id, calendar_date)`

> **注意**：这张表**不存 day_type**。法定属性只能来自 `work_calendar`，个人覆盖只表达"这天安排他上班"。合并成一个字段就等于允许把法定节假日改写成工作日，等于合法规避 3 倍加班费。

### 8.8 `attendance_punch_raw` 原始打卡流水

**只追加，永不修改。** 所有更正走补卡/申诉，不更新本表。

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| emp_no | varchar(20) | 是 | null | 识别出的工号；未认领时为 null |
| device_user_no | varchar(30) | 是 | null | 设备用户号（得力 `user_id` / 设备工号） |
| punch_time | datetime | 否 | | 打卡时间，精确到秒 |
| punch_date | date | 否 | | 打卡日期（冗余，用于索引与分区） |
| terminal_sn | varchar(50) | 是 | null | 设备 SN；手机打卡为设备 ID；补签为 `apply` |
| punch_type | varchar(20) | 否 | | FACE人脸 / FINGERPRINT指纹 / CARD刷卡 / PASSWORD密码 / MOBILE_GPS / MOBILE_WIFI / FIELD外勤 / REISSUE补签申请 / FLEXIBLE自动补卡 |
| punch_source | varchar(20) | 否 | | DEVICE_IMPORT设备文件导入 / PUSH设备推送 / CLOUD_PULL云平台拉取 / PROCESSING中间件轮询 / MANUAL手工 |
| import_batch_id | bigint | 是 | null | 导入批次；非文件导入为 null |
| raw_seq | varchar(50) | 是 | null | 厂商原始记录 ID，用于去重 |
| is_claimed | tinyint(1) | 否 | 0 | 是否已匹配到员工 |
| claim_remark | varchar(200) | 是 | null | 未认领原因 |

索引：
- `uk_attendance_punch_raw_dedup(punch_source, terminal_sn, device_user_no, punch_time)`
- `idx_attendance_punch_raw_emp_no_punch_date(emp_no, punch_date)`
- `idx_attendance_punch_raw_punch_date(punch_date)`

> **分区建议**：按 `punch_date` 做 RANGE 分区（按月），年数据量约 302 人 × 2 次 × 365 天 ≈ 22 万条，量不大，前期不分区也可，预留分区键。

### 8.9 `attendance_punch_import_batch` 导入批次

对应 `HR-ATT-29`（v1.0 的打卡数据入口）。

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| batch_no | varchar(30) | 否 | | 批次号 |
| file_name | varchar(200) | 否 | | 原始文件名 |
| file_hash | varchar(64) | 否 | | 文件 SHA-256，防重复导入 |
| total_rows | int | 否 | 0 | 总行数 |
| success_rows | int | 否 | 0 | 成功行数 |
| fail_rows | int | 否 | 0 | 失败行数 |
| unclaimed_rows | int | 否 | 0 | 未匹配到工号的行数 |
| status | varchar(20) | 否 | 'PENDING' | PENDING待处理 / PROCESSING处理中 / SUCCESS成功 / PARTIAL部分成功 / FAILED失败 |
| error_file_path | varchar(300) | 是 | null | 错误行回显文件路径 |
| import_by | bigint | 是 | null | 导入人 |
| import_at | datetime(3) | 是 | null | 导入时间 |

索引：`uk_attendance_punch_import_batch_batch_no(batch_no)`、`uk_attendance_punch_import_batch_file_hash(file_hash)`

### 8.10 `device_user_relation` 设备用户号映射

没有这张表，导入的打卡对不上人（`HR-ATT-29` 的前置）。

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| emp_no | varchar(20) | 否 | | 工号 |
| device_user_no | varchar(30) | 否 | | 设备用户号 |
| terminal_sn | varchar(50) | 是 | null | 限定设备；null 表示全球通用 |
| is_active | tinyint(1) | 否 | 1 | 是否有效 |

索引：`uk_device_user_relation_terminal_sn_device_user_no(terminal_sn, device_user_no)`

### 8.11 `attendance_day_result` 考勤日结果（核心表）

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| employee_id | bigint | 否 | | 员工 |
| organization_id | bigint | 否 | 0 | 所属组织**快照**（计算时取自 employment） |
| legal_entity_id | bigint | 否 | 0 | 所属法人**快照**（计算时取自 employment） |
| work_date | date | 否 | | 考勤日期 |
| shift_id | bigint | 是 | null | 当日班次；休息日为 null |
| rule_id | bigint | 是 | null | 生效规则 |
| rule_version | int | 是 | null | 规则版本（**快照**） |
| calendar_version | int | 是 | null | 工作日历版本（**快照**） |
| day_type | varchar(20) | 否 | | 当日法定属性（来自 work_calendar）：WORKDAY / RESTDAY / HOLIDAY |
| is_arranged | tinyint(1) | 否 | 0 | 是否安排了上班（含个人覆盖） |
| is_required | tinyint(1) | 否 | 0 | 是否应出勤：仅 WORKDAY + 已安排 时为 1 |
| required_minutes | int | 否 | 0 | 应出勤分钟 |
| worked_minutes | int | 否 | 0 | 实际在岗分钟 |
| late_minutes | int | 否 | 0 | 迟到分钟 |
| early_minutes | int | 否 | 0 | 早退分钟 |
| absent_minutes | int | 否 | 0 | 缺勤分钟 |
| absent_type | varchar(20) | 是 | null | NONE无 / LATE迟到 / EARLY早退 / MISSING缺卡 / ABSENT旷工 |
| missing_punch_count | tinyint | 否 | 0 | 缺卡次数 |
| overtime_workday_minutes | int | 否 | 0 | 工作日加班分钟（1.5 倍） |
| overtime_restday_minutes | int | 否 | 0 | 休息日加班分钟（2 倍） |
| overtime_holiday_minutes | int | 否 | 0 | 法定节假日加班分钟（3 倍） |
| leave_minutes | int | 否 | 0 | 请假分钟 |
| status | varchar(20) | 否 | NORMAL | 当日状态：NORMAL / ABNORMAL / LEAVE / TRIP / REST / HOLIDAY。旷工直接记 ABNORMAL，不设待定态 |
| calc_batch_no | varchar(30) | 是 | null | 计算批次号（重算时可追溯） |
| is_locked | tinyint(1) | 否 | 0 | 是否已随月度结算锁定 |

索引：
- `uk_attendance_day_result_employee_id_work_date(employee_id, work_date)`
- `idx_attendance_day_result_work_date_is_locked(work_date, is_locked)`
- `idx_attendance_day_result_calc_batch_no(calc_batch_no)`
- `idx_attendance_day_result_organization_id(organization_id)`
- `idx_attendance_day_result_legal_entity_id(legal_entity_id)`

> **为什么必须存 `rule_version` / `calendar_version`**：规则和日历会变。半年后被问"10 月 8 号为什么算我旷工"，必须能还原当时的判定依据。只存 `rule_id` 不够——规则内容可能已被改。

### 8.12 其余考勤表

| 表 | 关键字段 | 说明 |
|---|---|---|
| `attendance_exception` | employee_id, organization_id, legal_entity_id, work_date, exception_type, description, handled_status, handled_by | 异常台账，供异常清单与推送 |
| `attendance_appeal` | employee_id, organization_id, legal_entity_id, work_date, appeal_type, appeal_punch_time, reason, attach_path, approval_instance_id, approval_status | 申诉补卡。**补卡不写原始流水，写这里**（`HR-ATT-09`） |
| `overtime_apply` | employee_id, organization_id, legal_entity_id, work_date, start_time, end_time, apply_hours, confirm_hours, overtime_kind, reason, approval_instance_id, approval_status | 加班单。`confirm_hours` 是审批后与实际打卡比对的结果（`HR-ATT-10`） |
| `attendance_month_close` | legal_entity_id, close_month, close_status, close_by, close_at | 月度结算锁。`uk(legal_entity_id, close_month)` |
| `attendance_adjust_order` | employee_id, work_date, adjust_field, before_value, after_value, reason, approval_instance_id | 锁定后的考勤调整单（`HR-ATT-13`） |

---

## 九、F 域 · 假期

| 表 | 关键字段 | 说明 |
|---|---|---|
| `leave_type` | type_code, type_name, is_paid, is_statutory, min_unit, need_attachment_days, max_days_per_year | 假期类型。`is_statutory` 区分法定假与公司假 |
| `leave_quota` | employee_id, organization_id, legal_entity_id, leave_type_id, quota_year, total_days, used_days, remain_days, carried_over_days | 年度额度。`uk(employee_id, leave_type_id, quota_year)` |
| `leave_quota_log` | quota_id, employee_id, leave_type_id, change_type, change_days, before_remain, after_remain, ref_order_no | 额度流水。发放/使用/调整/结转/清零全记 |
| `leave_apply` | employee_id, organization_id, legal_entity_id, leave_type_id, start_time, end_time, leave_days, leave_hours, reason, attach_path, approval_instance_id, approval_status | 请假单。**跨类型自动拆分**时生成多条明细 |

---

## 十、G 域 · 薪酬

### 10.1 `salary_item` 薪资项目

| 字段 | 类型 | 空 | 默认 | 说明 |
|---|---|---|---|---|
| item_code | varchar(30) | 否 | | 项目编码 |
| item_name | varchar(50) | 否 | | 项目名称 |
| item_type | varchar(20) | 否 | | INCOME收入项 / DEDUCTION扣款项 / EMPLOYER_COST公司承担项 |
| calc_type | varchar(20) | 否 | | FIXED固定 / FORMULA公式 / ATTENDANCE考勤联动 / PIECE计件 / MANUAL手工 |
| formula_expr | varchar(500) | 是 | null | 计算公式（`calc_type=FORMULA` 时使用） |
| is_taxable | tinyint(1) | 否 | 1 | 是否计入计税基数 |
| is_insurance_base | tinyint(1) | 否 | 0 | 是否计入社保基数 |
| sort_no | int | 否 | 0 | 计算顺序，**有依赖关系时顺序很重要** |

### 10.2 其余薪酬表

| 表 | 关键字段 | 说明 |
|---|---|---|
| `salary_plan` | plan_code, plan_name, legal_entity_id, effective_from, effective_to, is_enabled | 薪资方案，**按法人/业态配置** |
| `salary_plan_item` | plan_id, item_id, sort_no, default_value | 方案包含的项目 |
| `grade_salary_standard` | grade_id, salary_plan_id, step_no, base_salary, effective_from | 职级薪档标准。**薪资数据暂缺，表先建、不填值** |
| `social_insurance_plan` | plan_name, city_code, insurance_year, effective_from | 社保方案（按参保城市） |
| `social_insurance_plan_item` | plan_id, insurance_type, person_rate, company_rate, base_min, base_max | 社保明细项（养老/医疗/失业/工伤/生育/公积金） |
| `salary_calc_batch` | batch_no, close_month, legal_entity_id, calc_status, calc_by, calc_at, total_amount | 算薪批次。**试算与正式分开，试算不产生正式数据** |
| `salary_detail` | batch_no, employee_id, organization_id, legal_entity_id, close_month, gross_amount, deduction_amount, net_amount, is_formal | 薪资明细头 |
| `salary_detail_item` | detail_id, item_id, item_name, amount | 薪资明细行。**必须存 item_name 快照**，防止项目改名后历史失真 |

**计件相关**（`HR-PAY-05/06`）另需两张表：

| 表 | 关键字段 | 说明 |
|---|---|---|
| `piece_rate` | product_code, process_code, unit_price, effective_from, effective_to, version_no | 工序单价表 |
| `piece_output` | employee_id, organization_id, legal_entity_id, work_date, product_code, process_code, output_qty, unit_price, amount, order_no | 产量记录。**能追溯到"某人某天做了哪道工序多少件"** |

---

## 十一、H / I 域

### 11.1 H 社保

| 表 | 关键字段 |
|---|---|
| `social_insurance_account` | employee_id, plan_id, insurance_no, join_date, quit_date, base_amount, status |
| `social_insurance_change` | employee_id, change_type(INCREASE增员/DECREASE减员/BASE_ADJUST基数调整), effective_month, before_base, after_base, order_no |

### 11.2 I 系统扩展

| 表 | 用途 |
|---|---|
| `approval_flow` | 审批流模板：flow_code, flow_name, biz_type, condition_expr, is_enabled |
| `approval_flow_node` | 审批节点：flow_id, node_no, node_name, approver_type(ROLE/USER/LEADER), approver_value, amount_min, amount_max |
| `approval_instance` | 审批实例：flow_id, biz_type, biz_id, initiator_id, status, current_node_no |
| `data_scope_rule` | 数据权限规则：role_id, scope_type(ALL/COMPANY/ORG_TREE/ORG/CUSTOM), scope_value, can_export |
| `biz_change_log` | 业务变更日志：table_name, biz_id, field_name, before_value, after_value, operator_id, operator_ip |

---

## 十二、关键设计问题与决策

### 12.1 员工"在哪个部门"靠 `employment`，不靠组织版本

最初考虑给 `organization` 做版本表（同一节点多版本、带生效区间）。实际不需要：

- "某人某时在哪个部门" → 查 `employment`（`start_date` / `end_date` 区间覆盖该时点）
- "组织某时是什么形态" → 查 `organization_history` 的变更流水

这样组织树本身只存当前，查询简单；历史追溯靠任职区间。代价是"还原某天的完整组织树结构"需要重放变更流水，一期不做这个功能。

### 12.2 打卡原始流水与考勤结果分离

见 8.8 与 8.11。合并成一张表，任何规则调整都会污染原始数据，且无法举证。

### 12.3 薪资明细必须存项目名称快照

`salary_detail_item` 存 `item_name`，不只存 `item_id`。否则某年把"岗位津贴"改名为"岗位补贴"，历史工资条全变。这是审计红线。

### 12.4 身份证/银行卡用「密文 + 哈希 + 脱敏值」三件套

加密值每次加密结果不同（IV 不同），无法建唯一索引。所以：

| 字段 | 用途 |
|---|---|
| `xxx_cipher` | 存储，AES-256-GCM |
| `xxx_hash` | SHA-256，**唯一索引**，用于查重 |
| `xxx_mask` | 列表展示，如 `513***273X` |

严禁在 `xxx_cipher` 上建索引或做 like 查询。

### 12.5 不使用物理外键

应用层保证一致性，数据库不建 `foreign key`。理由：批量迁移、逻辑删除、分区表都会与物理外键冲突。

### 12.6 枚举用英文码不用数字

老系统用 `YH/WH/SO/LY` 这种拼音缩写、或 `1/2/3` 数字码，可读性差且换人接手就看不懂。新系统统一英文大写码，前端用字典翻译。

### 12.7 月结锁的单一事实来源

锁存在两处，必须定清主从关系，否则会出现"月度表已结算、日结果还能改"的漏洞：

| 表 | 角色 |
|---|---|
| `attendance_month_close.close_status` | **唯一事实来源** |
| `attendance_day_result.is_locked` | 冗余加速字段，仅供查询过滤 |

**约束**：

1. 结算流程三步在同一事务内：写 `CLOSING` → 批量置 `is_locked=1` → 写 `CLOSED`
2. 重算接口校验顺序：**先查月度结算表，再查 `is_locked`**。两者不一致时以月度表为准，并写异常日志
3. 必须有对账任务：每日比对两表，出现"月表已关但日结果未锁"立即告警

> 为什么允许冗余：日结果按月至少 9,000 条，每次重算都要 join 月度表判断锁定状态，性能上不划算。但冗余字段必须有对账机制兜底，否则迟早不一致。

### 12.8 考勤规则版本不可就地修改

`attendance_rule` 的唯一键是 `(scope_type, scope_id, rule_version, effective_from)`：

- **允许**同一版本号对应多个生效区间（春节常白班 + 平时两班倒，可同为 version 1，靠生效日区分）
- **不允许**就地修改已生效的规则。改动一律"新建 version+1 + 停用旧版"

理由同 12.3：日结果存的是 `rule_version` 快照。就地改内容，历史结果指向的版本含义就变了。

---

## 十三、数据权限实现

对应 `HR-SYS-01/02`。

```
data_scope_rule
├── scope_type = ALL           → 集团 HR，看全量
├── scope_type = COMPANY       → scope_value = legal_entity_id，看本公司
├── scope_type = ORG_TREE      → scope_value = org_id，看该组织及其子树
├── scope_type = ORG           → scope_value = org_id，只看本组织
└── scope_type = SELF          → 仅本人，employee_id = 当前用户
```

**实现方式**：登录时把该用户所有角色的 `data_scope_rule` 解析成一组 `(org_path 前缀 / legal_entity_id / employee_id)`，缓存到 Redis。查询时在 SQL 里拼条件；**多角色取并集，无规则默认拒绝（`1=0`），任一角色 `ALL` 则不加条件**。

**事务表的组织快照**：`attendance_day_result`、`attendance_exception`、`attendance_appeal`、`overtime_apply`、`leave_quota`、`leave_apply`、`salary_detail`、`piece_output` 八张表**冗余 `organization_id` + `legal_entity_id`**，写入时从 `employment` 取当时值。原因：这些表只有 `employee_id`，若 join 当前任职过滤，员工调岗后历史数据会"跟着跑到新部门"，原主管看不到自己任期内的人；冗余快照既保证历史归属正确，也避免每次查询 join。

> `scope_type` 取值以 DDL 为准：`ALL / COMPANY / ORG_TREE / ORG / SELF`（早期文档写的 `CUSTOM` 作废）。

**禁止**在业务代码里写 `if (role == 'ADMIN')` 这种判断。权限一律走规则表。

---

## 十四、待确认 / 需评审的点

| # | 事项 | 影响 |
|---|---|---|
| 1 | 是否接受**不用 `sys_dept`**、自建 `organization` 与数据权限 | 偏离底座标准功能，需要团队认同 |
| 2 | 考勤日结果是否按天预生成（302 人 × 365 天 ≈ 11 万条/年），还是按需计算 | 影响性能方案与定时任务设计 |
| 3 | 薪资明细是否需要按月中调薪分段计算（一个月内两种薪资） | 影响 `salary_detail` 是否要按区间拆行 |
| 4 | 计件的产量数据一期是否落 `piece_output` 表，还是只录入汇总金额 | 影响计件可追溯性 |
| 5 | 是否需要"组织某时点完整快照"功能 | 一期建议不做，靠 `organization_history` 重放 |
| 6 | 是否需要多语言 / 多时区 | 当前不需要，字段预留 `varchar(50)` 而非 `varchar(20)` 便于扩展 |

---

## 十五、下一步

评审通过后，产出：

1. **建表 DDL**（含注释、索引、初始化数据：12 级职级、字典项、集团法人）
2. **ER 图**（按域拆分，避免一张图画 52 个表）
3. **接口清单**（按域，含请求/响应字段，对应需求编号）
4. **考勤计算引擎的算法说明**（规则继承链 + 打卡匹配 + 加班认定），这块最需要单独说清
