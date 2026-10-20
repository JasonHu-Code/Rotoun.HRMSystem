# HR 系统 · M0 底座改造清单 V0.1

> 对应：技术方案评审 **T-01（P0，阻塞 M0 开工）**
> 目标：M0 结束时达到"**能登录、菜单可见、数据权限按 `organization` 生效**"
> 输入：《技术方案 V0.1》第 2/5 章、《数据库设计 V0.1》第 4/13 章、`01~05` 建表脚本
> 状态：**已确认并执行（2026-10-20）**。底座机制已确认：RuoYi-Vue-Plus 5.x + `PlusDataPermissionHandler`；N-01 的 8 张表快照列已落脚本并通过 MySQL 实测；技术方案已转「已确认」，可进 M0。

---

## 〇、一页结论

### 三件事怎么落

| # | 事项 | 结论 |
|---|---|---|
| 1 | `sys_user` 怎么绑 `organization` | **不给 `sys_user` 加字段**。链路：`sys_user.user_id ← employee.sys_user_id → employment(is_current=1, PRIMARY).organization_id → organization.id`。`sys_user.dept_id` 保留，但降级为"底座兼容值"，业务查询一律不用 |
| 2 | 怎么覆盖底座数据权限 | **不"覆盖类"，做隔离**。先确认底座是 `DataScopeAspect`（RuoYi-Vue 原版）还是 `PlusDataPermissionHandler`（Plus 5.x），再用"禁用底座切面/Handler + 注册自己的 `DataPermissionInterceptor`"实现，两条路最终都收敛到同一个 `HrDataPermissionHandler` |
| 3 | `sys_role.data_scope` 怎么废弃 | **不删列**。三步：① 停止读取 ② 值迁移到 `data_scope_rule` ③ 保留字段 + 页面禁用 + 启动告警 |

### 本次核对新发现的 3 个问题（技术方案没写）

| # | 问题 | 影响 | 处理 |
|---|---|---|---|
| **N-01** | **考勤、假期、薪酬的业务表只有 `employee_id`，没有 `organization_id`**（已逐表核对） | `@DataScope(orgAlias="o")` 在这些表上无列可拼；join 当前任职会把历史数据算到新部门 | ✅ **已执行**：8 张表已加组织/法人快照列，脚本重跑两遍通过（见 README 第三轮） |
| **N-02** | 技术方案 5.3 写的 `DataScopeAspect` 是 **RuoYi-Vue 原版**叫法；RuoYi-Vue-Plus 5.x 主线用的是 `@DataPermission` + `PlusDataPermissionHandler` | 按错的类名去找覆盖点，M0 第一天就会卡住 | 开工前 10 分钟跑 `grep` 确认，两条分支都给了落法（第 3.2 / 3.3 节） |
| **N-03** | `data_scope_rule.scope_type` 在数据库设计文档里写 `ALL/COMPANY/ORG_TREE/ORG/CUSTOM`，在 `05_schema_system.sql` 里写 `ALL/COMPANY/ORG_TREE/ORG/SELF` | `CUSTOM` 与 `SELF` 两个口径打架，代码取值会错 | **以 DDL 为准**：`ALL / COMPANY / ORG_TREE / ORG / SELF`，文档同步修正 |

---

## 一、底座现状与本系统的冲突

| 维度 | RuoYi 底座 | 本系统 | 冲突 |
|---|---|---|---|
| 组织树 | `sys_dept(dept_id, parent_id, ancestors)` | `organization(id, parent_id, org_path, legal_entity_id)` | 两套 ID、两套路径算法 |
| 用户归属 | `sys_user.dept_id` | `employee.sys_user_id` + `employment.organization_id` | 一个用户可有多段任职；用户表单字段存不下 |
| 数据权限来源 | `sys_role.data_scope` + `sys_role_dept` | `data_scope_rule(role_id, scope_type, scope_value, can_export)` | 两套来源并存，谁生效没定 |
| 数据权限实现 | `DataScopeAspect`（原版）/ `PlusDataPermissionHandler`（Plus 5.x） | 计划用 `@DataScope` 注解 | **同名冲突**，且注解名与底座重名 |
| 业务表组织列 | 底座表都有 `dept_id` | 考勤/假期/薪酬表**只有 `employee_id`** | 拦截器无列可拼（N-01） |

**目标链路**（M0 完成后，任意业务查询都能拿到这组上下文）：

```
登录
 └─ sys_user.user_id
     └─ employee.sys_user_id            （1:1，可为空：纯管理员）
         └─ employment (is_current=1, employment_type='PRIMARY')
             ├─ organization_id → organization.id
             │                     ├─ org_path = '/1/3/15/'
             │                     └─ legal_entity_id
             └─ position_id → position.grade_id
```

---

## 二、T-01.1 `sys_user` 与 `organization` 的绑定

### 2.1 绑定链路（唯一事实来源）

```sql
-- 一条 SQL 拿到"当前登录用户是谁、在哪个组织、哪个法人"
SELECT u.user_id,
       e.id            AS employee_id,
       e.emp_no,
       em.organization_id,
       o.org_path,
       o.legal_entity_id,
       em.position_id
FROM sys_user u
LEFT JOIN employee e   ON e.sys_user_id = u.user_id AND e.is_deleted = 0
LEFT JOIN employment em ON em.employee_id = e.id
                       AND em.is_current = 1
                       AND em.employment_type = 'PRIMARY'
                       AND em.is_deleted = 0
LEFT JOIN organization o ON o.id = em.organization_id AND o.is_deleted = 0
WHERE u.user_id = ?;
```

### 2.2 三条设计决策

1. **不在 `sys_user` 上加 `organization_id` 字段。**
   - 一个员工可能兼岗（`employment_type=CONCURRENT`），单字段只能存一个；
   - 可能跨法人派驻（`employment.legal_entity_id` ≠ `organization.legal_entity_id`）；
   - 组织会变，用户表加字段会变成"第二个事实来源"，一定会不一致。
2. **`employee.sys_user_id` 加唯一索引**（MySQL 唯一索引允许多个 `NULL`，正好支持"有员工无账号"和"有账号无员工"两种情况）。
3. **离职不删绑定**：`employee_status` 改为 `RESIGNED` 时停用 `sys_user`、清 token，但保留 `employee.sys_user_id`，供审计与返聘复用。

### 2.3 `sys_user.dept_id` 怎么处理

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| **A（推荐）** | 保留字段；创建用户/调岗时写入主岗 `organization_id`，仅作底座兼容值与日志显示 | 不改底座页面；升级不冲突 | 存在"第二份数据"，需要靠规范约束 | **选 A** |
| B | 置 `0`/`NULL`，彻底不用 | 最干净 | 底座用户管理页"所属部门"全空；部分底座 SQL 可能异常 | 不选 |
| C | 把 `dept_id` 外键改指 `organization.id` | 语义统一 | 改底座表结构，升级难合并；`sys_dept` 相关 SQL 全要改 | 不选 |

**配套硬约束**（写进开发规范）：

- 业务代码**禁止**用 `sys_user.dept_id` 做任何查询条件或数据权限判断；
- 底座"用户管理"页面只给系统管理员用，不分配给公司 HR / 主管；
- 代码评审时 `grep "dept_id"` 出现在 `com.hr.biz` 下一律打回。

### 2.4 DDL 改动（M0 执行）

```sql
-- 1. 员工与账号 1:1（允许多个 NULL）
ALTER TABLE `employee`
  ADD UNIQUE KEY `uk_employee_sys_user_id` (`sys_user_id`);

-- 2. sys_user.dept_id 只加注释，不改类型、不加外键
ALTER TABLE `sys_user`
  MODIFY COLUMN `dept_id` bigint NULL DEFAULT NULL
  COMMENT '底座兼容字段，仅作展示；业务归属见 employment.organization_id';

-- 3. 可选：只读视图，方便联表核对
CREATE OR REPLACE VIEW `v_user_org` AS
SELECT u.user_id, u.user_name, u.nick_name,
       e.id AS employee_id, e.emp_no,
       em.organization_id, o.org_name, o.org_path, o.legal_entity_id,
       em.position_id, em.employment_type
FROM sys_user u
LEFT JOIN employee e    ON e.sys_user_id = u.user_id AND e.is_deleted = 0
LEFT JOIN employment em ON em.employee_id = e.id AND em.is_current = 1
                       AND em.employment_type = 'PRIMARY' AND em.is_deleted = 0
LEFT JOIN organization o ON o.id = em.organization_id AND o.is_deleted = 0;
```

> `employee.sys_user_id` 已有字段（`02_schema_employee.sql` 第 51 行），只补唯一索引，不改列。

### 2.5 登录上下文 `HrLoginContext`

不改底座 `LoginUser` 类（避免动 `ruoyi-common`），新增独立上下文对象，登录成功后装配一次：

```java
public class HrLoginContext {
    private Long userId;
    private Long employeeId;        // 可空：纯管理员
    private Long organizationId;    // 主岗组织
    private Long legalEntityId;     // 主岗组织所属法人
    private String orgPath;         // '/1/3/15/'
    private Long positionId;
    private Set<String> roleCodes;
    private List<DataScopeRule> scopeRules;
    private boolean canExport;      // 任一规则 can_export=1
}
```

| 项 | 约定 |
|---|---|
| 存储 | Redis `hr:login:{userId}`，TTL 与 token 一致 |
| 续期 | token 滑动续期时同步 `expire` |
| 装配失败 | 允许登录，但 `employeeId=null`；业务接口返回 **403 + "账号未绑定员工档案"**，不返回 500 |
| 纯管理员 | `employeeId=null`，若其规则只有 `SELF` → 运行时 `1=0`，并在启动校验里告警 |
| 调岗 | 清 `hr:login:{userId}` + `hr:datascope:{userId}`，下次请求重装配 |

### 2.6 初始化顺序与校验

```
1. legal_entity（13 法人）
2. organization（组织树，先父后子，生成 org_path）
3. position / position_grade（职位与职级）
4. employee（302 人）
5. employment（主岗，is_current=1）
6. sys_user（按工号建账号）
7. 回填 employee.sys_user_id
8. 分配角色
```

校验 SQL（M0 验收必跑）：

```sql
-- 应为 0（除纯管理员）
SELECT COUNT(*) FROM employee e
WHERE e.is_deleted = 0 AND e.sys_user_id IS NULL;

-- 应无结果：一个员工绑了多个账号
SELECT sys_user_id, COUNT(*) FROM employee
WHERE sys_user_id IS NOT NULL AND is_deleted = 0
GROUP BY sys_user_id HAVING COUNT(*) > 1;

-- 应无结果：一个账号绑了多个员工
SELECT e.sys_user_id, COUNT(*) FROM employee e
WHERE e.sys_user_id IS NOT NULL AND e.is_deleted = 0
GROUP BY e.sys_user_id HAVING COUNT(*) > 1;

-- 应无结果：用户有账号但无当前主岗任职
SELECT u.user_id FROM sys_user u
LEFT JOIN employee e ON e.sys_user_id = u.user_id AND e.is_deleted = 0
LEFT JOIN employment em ON em.employee_id = e.id AND em.is_current = 1
                       AND em.employment_type = 'PRIMARY' AND em.is_deleted = 0
WHERE u.del_flag = '0' AND em.id IS NULL;
```

---

## 三、T-01.2 覆盖底座数据权限

### 3.1 底座机制已确认（2026-10-20）

**结论：RuoYi-Vue-Plus 5.x，数据权限走 `PlusDataPermissionHandler`（实现 MyBatis-Plus 的 `MultiDataPermissionHandler`），由 `DataPermissionInterceptor` 注册。** 采用 3.3 的方案；3.2 的 `DataScopeAspect` 分支仅作备案，不再作为可选路径。

开工时仍建议跑一遍下面的命令做 sanity check（防止脚手架版本被替换过）：

```bash
grep -rn "PlusDataPermissionHandler\|DataPermissionInterceptor" --include=*.java .
grep -rn "DataScopeAspect" --include=*.java .   # 应无命中
grep -rn "params.dataScope" --include=*.xml .  # 应无命中
```

| 检查项 | 期望 | 不符合时 |
|---|---|---|
| `PlusDataPermissionHandler` | 存在 | 检查是否被裁剪；若确实没有，按 3.3 自建 Handler |
| `DataScopeAspect` | 不应存在 | 存在说明混入了 RuoYi-Vue 原版代码，需排除 |
| `params.dataScope` | 不应存在 | 存在则有 SQL 注入风险，必须清掉 |

> **技术方案 5.3 已同步**：原文写的 `DataScopeAspect` 已改为 `PlusDataPermissionHandler`，代码示例的注解改为 `@HrDataScope`，避免与底座 `@DataPermission` 重名。

### 3.2 分支 A：`DataScopeAspect`（原版，已排除，仅作备案）

原版机制：AOP 在方法执行前把 `and (dept_id in ...)` 拼进 `BaseEntity.params.dataScope`，XML 里用 `${params.dataScope}` 输出。

**做法：停用底座切面 + 不给自己标 `@DataScope` + 改用 MyBatis-Plus 拦截器。**

1. 在 `hr-framework` 里删除/注释 `DataScopeAspect` 类（或加 `@ConditionalOnProperty` 关掉）；确认 `ruoyi-system` 的 mapper XML 里 `params.dataScope` 一并清掉。
2. 底座 `sys_user` / `sys_role` 查询不再注入任何数据权限（管理员配置页本就该全量，用菜单权限控制谁能进）。
3. 业务侧统一用**自己的注解 `@HrDataScope`**（不叫 `@DataScope`，彻底避开重名），由 MyBatis-Plus 的 `DataPermissionInterceptor` 处理，见 3.4。

```java
// 我们的注解，与底座 @DataScope 无任何关系
@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
public @interface HrDataScope {
    String orgAlias() default "o";   // 组织列别名
    String empAlias() default "e";   // 员工列别名
    String legalAlias() default "o"; // 法人列别名
}
```

> 如果底座是 jar 依赖、不能删源码：用 `@ComponentScan.Filter` 排除该切面所在的包，或注册 `BeanDefinitionRegistryPostProcessor` 在启动时移除 `dataScopeAspect` bean。**不要**用同名类去"覆盖"，类加载顺序不可控。

### 3.3 采用方案：`PlusDataPermissionHandler`（Plus 5.x）

Plus 5.x 机制：`MybatisPlusConfig` 里注册 `DataPermissionInterceptor`，其 `MultiDataPermissionHandler` 读 `@DataPermission` 注解 + `sys_role.data_scope` 生成 SQL。

**做法：不注册底座 Handler，注册我们自己的。**

```java
@Configuration
public class HrMybatisConfig {

    @Bean
    public MybatisPlusInterceptor mybatisPlusInterceptor(HrDataPermissionHandler hrHandler) {
        MybatisPlusInterceptor interceptor = new MybatisPlusInterceptor();
        // 只挂我们自己的 Handler，底座的 PlusDataPermissionHandler 不再注册
        interceptor.addInnerInterceptor(new DataPermissionInterceptor(hrHandler));
        interceptor.addInnerInterceptor(new PaginationInnerInterceptor(DbType.MYSQL));
        return interceptor;
    }
}
```

```java
@Component
public class HrDataPermissionHandler implements MultiDataPermissionHandler {

    @Override
    public Expression getSqlSegment(Table table, Expression where, String mappedStatementId) {
        HrDataScope ann = HrDataScopeHolder.current();   // 从 @HrDataScope 取别名
        if (ann == null) {
            return null;                                  // 未标注 → 不注入
        }
        return new DataScopeSqlBuilder().build(table, ann);
    }
}
```

要点：

- 底座的 `PlusDataPermissionHandler` 不再作为 bean 注册（或 `@Primary` 让位）；
- 底座的 `sys_*` mapper 不标 `@HrDataScope`，因此不会被组织权限限制；
- 底座的 `@DataPermission` 注解即使还挂在 mapper 上也不会生效，因为 Handler 已换。

### 3.4 `DataScopeSqlBuilder`：规则 → SQL

**输入**：`HrLoginContext.scopeRules` + 当前表 / 别名
**输出**：JSqlParser `Expression`（或 `null` 表示无条件）

```java
public Expression build(Table table, HrDataScope ann) {
    HrLoginContext ctx = HrContextHolder.get();
    if (ctx == null || ctx.getScopeRules().isEmpty()) {
        return deny();                          // 1=0，默认拒绝
    }
    if (ctx.getScopeRules().stream().anyMatch(r -> "ALL".equals(r.getScopeType()))) {
        return null;                            // 任一角色 ALL → 无条件
    }

    List<Expression> ors = new ArrayList<>();
    for (DataScopeRule r : ctx.getScopeRules()) {
        switch (r.getScopeType()) {
            case "COMPANY" -> ors.add(eq(legalColumn(table, ann), r.getScopeValue()));
            case "ORG_TREE" -> ors.add(like(orgColumn(table, ann), ctx.pathOf(r.getScopeValue()) + "%"));
            case "ORG"      -> ors.add(eq(orgColumn(table, ann), r.getScopeValue()));
            case "SELF"     -> ors.add(eq(empColumn(table, ann), ctx.getEmployeeId()));
            default -> { /* 未知类型 → 忽略并告警 */ }
        }
    }
    return ors.isEmpty() ? deny() : new OrExpression(ors);
}
```

**四条硬规则**：

| # | 规则 | 理由 |
|---|---|---|
| 1 | **默认拒绝**：无规则 → `1=0` | 漏配权限时宁可看不到，不能全放 |
| 2 | **ALL 优先**：任一规则 `ALL` → 不加任何条件 | 避免 `OR 1=0` 把全量又收窄 |
| 3 | **多角色并集**：规则间 `OR` | 与业务预期一致（兼任两个角色应能看两边） |
| 4 | **列不存在 → 启动失败** | `orgColumn()` 找不到列时抛异常，不允许静默退化成全量 |

### 3.5 N-01：业务表没有组织列，怎么办（已执行）

已逐表核对（`03`/`04` 脚本）：

| 表 | `organization_id` | `legal_entity_id` | `employee_id` | 结论 |
|---|---|---|---|---|
| `attendance_day_result` | ✗ | ✗ | ✓ | **需加组织/法人快照** |
| `attendance_exception` | ✗ | ✗ | ✓ | 需加 |
| `attendance_appeal` | ✗ | ✗ | ✓ | 需加 |
| `overtime_apply` | ✗ | ✗ | ✓ | 需加 |
| `leave_apply` | ✗ | ✗ | ✓ | 需加 |
| `leave_quota` | ✗ | ✗ | ✓ | 需加 |
| `salary_detail` | ✗ | ✓ | ✓ | 需加组织 |
| `piece_output` | ✗ | ✗ | ✓ | 需加 |
| `employee` | ✗ | ✗ | ✓ | 查询时 join `employment`，不加列 |
| `employee_*` 子表 | ✗ | ✗ | ✓ | 通过 `employee_id` 子查询，不加列 |
| `attendance_punch_raw` | ✗ | ✗ | ✗ | 仅 HR 导入使用，不挂数据权限 |

**两个方案对比**：

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| **A（推荐）** | 8 张事务表加 `organization_id` + `legal_entity_id`，写入时从 `employment` 快照 | 查询不 join，索引可直接用；**历史归属正确**（按当时的组织，不受后来调岗影响）；与日结果快照 `rule_version` 的做法一致 | 写入时要记得填；8 张表各加 2 列 | **选 A** |
| B | Handler 退化为 `employee_id IN (SELECT ... FROM employment WHERE is_current=1 AND organization_id IN ...)` | 不改表 | 每次查询多一层子查询；**历史数据会按当前部门算**，调岗后原主管看不到历史；分页性能差 | 不选 |

**方案 A 的 ALTER（已执行，2026-10-20）**：

```sql
-- 以 attendance_day_result 为例，其余 7 张同构
ALTER TABLE `attendance_day_result`
  ADD COLUMN `organization_id` bigint unsigned NOT NULL DEFAULT 0 COMMENT '计算时所属组织快照' AFTER `employee_id`,
  ADD COLUMN `legal_entity_id` bigint unsigned NOT NULL DEFAULT 0 COMMENT '计算时所属法人快照' AFTER `organization_id`,
  ADD KEY `idx_adr_organization_id` (`organization_id`),
  ADD KEY `idx_adr_legal_entity_id` (`legal_entity_id`);
```

写入约定（服务层统一）：

- 考勤日结果：引擎 `DayContext` 里带 `organizationId`/`legalEntityId`，落库时写入；
- 请假/加班/申诉：提交时从 `employment` 取当前主岗写入；
- 薪资明细：按薪资所属月份取"该月有效的任职"写入。

> 这 8 张表当前是空表（未上线），加列无历史数据回填问题。**已重跑验证（3320 临时实例，2026-10-20）**：首跑与重复执行均通过，8 张表的两列与 16 个索引全部落库。

### 3.6 别名约定与启动校验

- 所有标注 `@HrDataScope` 的 mapper 方法，SQL 必须显式写别名：组织表 `o`、员工表 `e`、任职表 `em`；
- 注解显式声明：`@HrDataScope(orgAlias = "o", empAlias = "e")`，**不用默认值兜底**（默认值只用于单表场景）；
- 启动时扫描所有 `@HrDataScope` 方法，解析 `MappedStatement` 的 SQL，检查注解里的别名是否存在；不存在直接启动失败（fail-fast），不允许运行时才发现。

### 3.7 `can_export` 与敏感域叠加

| 场景 | 规则 |
|---|---|
| 导出权限 | 规则中**任一** `can_export=1` → 允许导出；全部为 0 → 导出接口返回 403 |
| 列表 vs 导出 | 列表按数据权限过滤；导出额外校验 `can_export`，不能"能看就能拿走" |
| 薪酬/银行卡 | 数据权限之外，**必须**叠加字段脱敏（`SYS-07`）+ 查看他人薪资二次验证（`SYS-08`）；数据权限不替代字段级控制 |
| 报表聚合 | **不走拦截器**，在 service 层把"可见组织 ID 集合 / 法人 ID 集合"作为查询参数传入，避免聚合 SQL 无法拼别名 |

### 3.8 缓存与失效

| Key | 内容 | TTL | 失效时机 |
|---|---|---|---|
| `hr:org:tree` | 全量组织（id/path/legalEntityId/status） | 1h | 组织新增/改名/移动/停用 |
| `hr:datascope:{userId}` | 规则快照 + 解析后的 path 前缀 | 30min | 角色规则变更、用户角色变更、调岗、离职 |
| `hr:login:{userId}` | `HrLoginContext` | 与 token 一致 | 调岗、离职、角色变更 |

**失效策略：一律全量清，不做精确失效。** 302 人、组织百来个，`DEL hr:datascope:*` 的成本远低于"漏清一个导致越权"的风险。

组织移动的额外处理：`org_path` 变化后必须递归更新所有子节点（MySQL 8 递归 CTE 或应用层遍历），并清 `hr:org:tree` + `hr:datascope:*`。这是 M1 的事，但 M0 的缓存设计要留好这个失效入口。

### 3.9 M0 验收用例（12 条）

| # | 场景 | 期望 |
|---|---|---|
| 1 | 集团 HR（`ALL`） | 看到全部 302 人 |
| 2 | 公司 HR（`COMPANY=法人A`） | 只看到法人 A 的人 |
| 3 | 部门主管（`ORG_TREE=部门X`） | 只看到 X 及子树 |
| 4 | 普通员工（`SELF`） | 只看到自己 |
| 5 | 兼任两角色（`COMPANY A` + `ORG_TREE X`） | 两边并集，无重复 |
| 6 | 无任何规则 | **0 条**（默认拒绝，不是全量） |
| 7 | 纯管理员（无 `employee`） | `ALL` 正常；仅 `SELF` 时 0 条并告警 |
| 8 | `can_export=0` | 列表可见、导出 403 |
| 9 | 组织移动后 | 按新 `org_path` 生效（缓存已清） |
| 10 | 分页查询 | 总数与列表一致（SQL 层过滤，非内存过滤） |
| 11 | 调岗后 | 原主管看历史考勤仍可见（快照列生效） |
| 12 | 未标 `@HrDataScope` 的 mapper | 不注入条件（如 `sys_dict`） |

---

## 四、T-01.3 废弃 `sys_role.data_scope`

### 4.1 三步走（不删列）

| 步 | 动作 | 产出 |
|---|---|---|
| 1 | **停止读取**：业务代码、Handler、切面一律不读 `sys_role.data_scope` | `grep -rn "data_scope"` 在 `com.hr.*` 下为 0（`sys_role` 实体除外） |
| 2 | **值迁移**：把现有角色的 `data_scope` + `sys_role_dept` 转成 `data_scope_rule` 记录 | 迁移脚本 + 迁移报告（成功/待确认） |
| 3 | **保留字段 + 标记废弃**：不删列；角色管理页隐藏/禁用"数据范围"；启动校验告警 | 注释 + `@Deprecated` + 前端禁用 |

**为什么不删列**：底座角色管理页、部分 mapper 仍可能引用；删列会导致底座页面报错、升级无法合并。保留一个"永不读取"的列，成本最低。

### 4.2 旧值 → 新规则映射

| `sys_role.data_scope` | 含义 | `data_scope_rule.scope_type` | `scope_value` |
|---|---|---|---|
| `1` | 全部数据 | `ALL` | 空 |
| `2` | 自定义数据 | 按 `sys_role_dept` 每条 → 一条 `ORG`（或 `ORG_TREE`） | 映射后的 `organization.id` |
| `3` | 本部门 | `ORG` | 角色 `dept_id` 映射后的 `organization.id` |
| `4` | 本部门及以下 | `ORG_TREE` | 同上 |
| `5` | 仅本人 | `SELF` | 空 |
| 空 / `0` | 未设置 | 不生成规则 | → 运行时 `1=0` |

### 4.3 前置条件：`sys_dept` → `organization` 映射

旧 `dept_id` 与新 `organization.id` **不是同一套 ID**。迁移前必须有一张映射表（属于 `HR-MIG-01` 编码映射的一部分）：

```sql
CREATE TABLE IF NOT EXISTS `mig_dept_org_map` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `old_dept_id` bigint unsigned NOT NULL COMMENT '旧 sys_dept.dept_id',
  `new_org_id` bigint unsigned DEFAULT NULL COMMENT '新 organization.id；NULL 表示待确认',
  `remark` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_mig_dept_org_map_old_dept_id` (`old_dept_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='旧部门→新组织映射（一次性迁移用）';
```

映射缺失时：该角色生成 `ORG` 但 `scope_value=NULL` → 运行时 `1=0`，并在迁移报告里列为"待人工确认"。**不能默认成 ALL。**

### 4.4 角色管理页面改造

| 位置 | 改造 |
|---|---|
| 底座「角色管理」的"数据范围"下拉 | **隐藏**（推荐）或置灰 + 提示"数据权限已迁移至【数据权限】页" |
| 新增「数据权限」页 | 按角色配置 `data_scope_rule`：范围类型、范围值（法人/组织树选择器）、是否可导出 |
| 角色新增接口 | 不再接收 `dataScope` 字段；即使传了也忽略，避免旧页面写回 |
| 角色列表 | 显示"已配置 N 条数据权限"，未配置的标红"未配置（看不到数据）" |

### 4.5 防回退

1. **启动校验**：`sys_role.data_scope` 非空且 `data_scope_rule` 无对应记录 → 打 WARN，列出角色。
2. **回归测试**：建两个角色，改 `sys_role.data_scope`，断言查询结果**不变**（证明只认 `data_scope_rule`）。
3. **代码检查**：CI 里加一条 `grep -rn "getDataScope\|data_scope" com/hr`，命中即失败（白名单 `sys_role` 实体）。

---

## 五、配套项（M0 一并做，否则数据权限跑不通）

### 5.1 员工账号生命周期（T-06）

| 事件 | 动作 |
|---|---|
| 入职 | 建 `sys_user`（账号=工号）→ 绑 `employee.sys_user_id` → 分配默认角色 → 清缓存 |
| 调岗 | 不换账号；更新 `employment` → 清 `hr:login` / `hr:datascope` |
| 离职 | `employee_status=RESIGNED` → 停用 `sys_user` → 清 token → **保留绑定** |
| 返聘 | 复用原 `sys_user`（工号不变），重新启用并重绑角色 |
| 兼岗 | 不改 `sys_user`；`employment` 增一条 `CONCURRENT`；数据权限按主岗算 |

### 5.2 `org_path` 维护

- 新增组织：`org_path = parent.org_path + newId + '/'`；
- 移动组织：递归更新子树 `org_path`（MySQL 8 递归 CTE）；
- 停用组织：不删物理行，`status=DISABLED`；路径保留，历史数据仍可解释；
- 任何路径变更 → 清 `hr:org:tree` + `hr:datascope:*`。

### 5.3 审计

- 数据权限**拒绝**也要留痕：`biz_change_log` 或独立 `access_denied_log` 记录 `userId / 接口 / 目标ID / 原因`；
- 导出行为单独记日志（谁、什么条件、多少条），满足 `SYS-08` 与审计要求。

---

## 六、M0 交付物清单

| # | 交付物 | 验收 |
|---|---|---|
| 1 | `employee.sys_user_id` 唯一索引 | DDL 执行成功，重复绑定插入失败 |
| 2 | `v_user_org` 视图（可选） | 查询返回用户-员工-组织-法人一行 |
| 3 | `HrLoginContext` + 登录装配 + Redis | 登录后能拿到 `employeeId/orgId/legalEntityId/orgPath` |
| 4 | `@HrDataScope` 注解 + `HrDataPermissionHandler` | 标注的 mapper 自动追加条件 |
| 5 | `DataScopeSqlBuilder`（5 种范围 + 并集 + 默认拒绝） | 12 条验收用例全过 |
| 6 | 隔离/禁用底座数据权限实现 | 底座页面不被组织权限误伤 |
| 7 | 8 张业务表组织/法人快照列 | ✅ 已执行：脚本两遍通过，8 表 16 个索引已核对 |
| 8 | `data_scope_rule` 初始化（集团 HR / 公司 HR / 主管 / 员工） | 4 类角色各看到预期数据 |
| 9 | `sys_role.data_scope` → `data_scope_rule` 迁移脚本 | 迁移报告无"待确认"或已人工处理 |
| 10 | 角色管理页改造（数据范围隐藏 + 数据权限页） | 新建角色默认看不到数据，需显式配置 |
| 11 | 启动校验（未迁移角色告警、别名缺失 fail-fast） | 故意配错能启动失败 |
| 12 | 缓存失效（角色/组织/调岗） | 改规则后 30 秒内生效（或立即清） |
| 13 | T-04 Token 头对齐（Sa-Token 配置 + 前端拦截器 + 8 条用例） | 带 `Authorization: Bearer` 调通；不带/错前缀/过期均 401 |

---

## 七、待确认

| # | 事项 | 我的建议 |
|---|---|---|
| 1 | ~~底座实际是 RuoYi-Vue 原版还是 RuoYi-Vue-Plus 5.x？~~ | ✅ **已确认：RuoYi-Vue-Plus 5.x + `PlusDataPermissionHandler`**，走 3.3 方案 |
| 2 | ~~8 张业务表是否加 `organization_id` + `legal_entity_id` 快照列？~~ | ✅ **已确认并执行**：8 张表已加，脚本首跑与重复执行均通过 |
| 3 | 纯管理员（无员工档案）是否允许登录业务端？ | 允许登录，但只给系统管理菜单；业务菜单不分配 |
| 4 | 返聘是否复用原账号？ | **复用**（工号不变），避免历史数据断链 |
| 5 | 报表聚合是否接受"service 层传可见组织集合"而非拦截器？ | **接受**。聚合 SQL 无法稳定拼别名，参数化更可靠 |

---

## 八、附：开工前 10 分钟核对脚本

```bash
# 1. 底座数据权限实现
grep -rn "DataScopeAspect\|PlusDataPermissionHandler\|DataPermissionInterceptor" --include=*.java .

# 2. 是否有 ${params.dataScope} 老写法
grep -rn "params.dataScope" --include=*.xml .

# 3. 底座角色与部门现状
mysql -uroot -p rt-hrms -e "SELECT role_id, role_name, data_scope FROM sys_role;"
mysql -uroot -p rt-hrms -e "SELECT COUNT(*) AS dept_cnt FROM sys_dept;"

# 4. 业务表组织列现状（应全部为 0）
mysql -uroot -p rt-hrms -e "
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema='rt-hrms' AND column_name IN ('organization_id','legal_entity_id')
ORDER BY table_name;"

# 5. 员工与账号绑定现状
mysql -uroot -p rt-hrms -e "
SELECT COUNT(*) AS no_user_emp FROM employee WHERE sys_user_id IS NULL AND is_deleted=0;"
```

---

## 九、T-04 认证与 Token 头对齐清单（M0 第一天）

### 9.1 一句话

Sa-Token 默认 `token-name = satoken`、无前缀；项目文档写 `Authorization: Bearer`。**先查底座实际配置，再决定"改配置跟随文档"还是"改文档跟随底座"。推荐前者**——保持 `Authorization: Bearer`，与前端、网关、Swagger 的习惯一致。

> **本方案已于 2026-10-20 确认（方案 A）。** M0 第一天只做两件事：① 按 9.2 核对底座现有配置；② 按 9.9 跑 8 条用例。若底座已经是 `Authorization` + `Bearer`，无需改配置，只把结论记进项目文档。

### 9.2 先查底座（5 分钟，别猜）

```bash
# 1. yml 里的 sa-token 配置
grep -rn -A 20 "sa-token:" --include=application*.yml --include=application*.yaml .

# 2. Java 侧是否另有覆盖（有些底座用 @Bean 改配置）
grep -rn "SaTokenConfig\|tokenName\|tokenPrefix\|isReadCookie" --include=*.java .

# 3. 登录返回体字段
grep -rn "class LoginVo\|access_token\|expire_in\|tokenName\|tokenPrefix" --include=*.java .
```

| 查到的现状 | 处理 |
|---|---|
| `token-name: Authorization` + `token-prefix: Bearer` | 已对齐，只需把结论写进文档，不改代码 |
| `token-name: Authorization`，无 `token-prefix` | 前端**不要**加 `Bearer `；或补上 prefix，二选一 |
| 默认 `satoken` / 无配置 | 按 9.3 配置成 `Authorization` + `Bearer` |
| Java Config 覆盖了 yml | 以 Java Config 为准，先改代码再改 yml |

### 9.3 推荐配置（方案 A：`Authorization` + `Bearer`）

```yaml
sa-token:
  token-name: Authorization      # 同时是 cookie 名
  token-prefix: Bearer           # 客户端发 "Bearer <token>"，中间恰好一个空格
  timeout: 28800                 # 8 小时（绝对有效期）
  active-timeout: 1800           # 30 分钟无操作冻结；-1 表示关闭
  is-concurrent: true            # 允许 PC 与后续 H5 同时在线
  is-share: false                # 每次登录新 token，便于单独踢下线
  token-style: uuid              # 不用 jwt：jwt 无状态，踢下线还要额外黑名单
  is-read-header: true
  is-read-cookie: false          # 只认 Header，避免浏览器自动带 cookie 形成第二入口
  is-read-body: false
  is-log: false
```

三个易错点：

1. `token-prefix` 是**字符串前缀比较**，大小写和空格必须完全一致；前端不要拼两次 `Bearer`。
2. `is-read-cookie: false` 必须显式关掉，否则 cookie 也能通过鉴权，等于多一个不受控入口。
3. `token-style: uuid` 而不是 `jwt`：本项目要支持"离职立即踢下线"，uuid + Redis 一句 `kickout` 就能做到；jwt 还要维护黑名单。

### 9.4 四个环节必须一致

| 环节 | 约定 | 易错点 |
|---|---|---|
| 登录响应 | `data.access_token`（或 `data.token`，**以底座 `LoginVo` 实际字段为准**）+ `expire_in` | 前端字段名写错，token 取不到 |
| 请求头 | `Authorization: Bearer <token>` | 多/少一个空格；重复拼成 `Bearer Bearer xxx` |
| 后端读取 | `StpUtil.getTokenValue()` | 手写 `request.getHeader()` 会绕过 prefix 处理 |
| 401 处理 | 后端 `NotLoginException` → 401；前端清 token 跳登录 | 把 401 当 500 弹"系统错误" |

前端 axios 拦截器（示意）：

```js
service.interceptors.request.use(config => {
  const token = getToken()
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})
```

### 9.5 `loginId` 必须用 `sys_user.user_id`

这条最容易被忽略，但错了会同时影响登录和踢下线：

- **纯管理员没有 `employee` 记录**，用 `employeeId` 作 loginId 会导致管理员登录不了；
- 离职踢下线是 `StpUtil.kickout(userId)`，用 `employeeId` 找不到会话；
- `HrLoginContext` 是按 `userId` 反查 `employee`，方向要一致。

```java
StpUtil.login(userId);                      // 不是 employeeId
Long userId = StpUtil.getLoginIdAsLong();
```

> 若底座默认把 `username` 当 loginId，要在登录处显式改成 `userId`，并确认 `StpUtil.getLoginIdAsLong()` 返回的是 `sys_user.user_id`。

### 9.6 "8 小时滑动续期"的真相

Sa-Token 的 `timeout` 是**绝对有效期**，`active-timeout` 是**无操作冻结**，两者都**不是滑动续期**。

| 方案 | 做法 | 代价 |
|---|---|---|
| A（推荐先用） | `timeout: 28800` + `active-timeout: 1800`，8 小时到点重新登录 | 简单、可预期；HR 系统日常够用 |
| B | 鉴权拦截器里按需调 `StpUtil.renewTimeout(28800)`（每 5 分钟最多一次） | 真正滑动；每次续期写 Redis，要控频 |

若选 B，`hr:login:{userId}` 的 TTL 必须同步 `expire`，否则会出现"token 还在、登录上下文先过期"。

### 9.7 离职踢下线

```java
StpUtil.kickout(userId);                 // 踢掉该用户全部会话
redis.delete("hr:login:" + userId);
redis.delete("hr:datascope:" + userId);
```

| 事件 | 是否踢 |
|---|---|
| 离职审批通过 / `employee_status = RESIGNED` | ✅ 踢，并停用 `sys_user` |
| 退休生效 | ✅ 踢 |
| 停薪留职 | ❌ 不踢（账号保留，业务菜单可收窄） |
| 返聘 | ❌ 不踢；复用原账号，重新启用 |

### 9.8 白名单与 CORS

- 放行：`/api/auth/login`、`/api/auth/captcha`、`/doc.html`、`/webjars/**`、`/v3/api-docs/**`、`/swagger-resources/**`、`/favicon.ico`；其余一律鉴权。
- CORS 的 `Access-Control-Allow-Headers` 必须含 `Authorization, Content-Type`，并放行 `OPTIONS` 预检。
- Nginx 反代默认透传 `Authorization`；若前面还有网关/WAF，确认没把它当敏感头剥掉。

### 9.9 验收用例（8 条）

| # | 场景 | 期望 |
|---|---|---|
| 1 | `Authorization: Bearer <正确 token>` | 200 |
| 2 | 不带 token | 401 |
| 3 | 只发 `<token>`、不带 `Bearer` | 401（或按配置明确接受，但不能两种都行） |
| 4 | `bearer` 小写 / 多一个空格 | 401 |
| 5 | 过期 token | 401 + 明确的 code |
| 6 | 离职后旧 token | 401（已被 kickout） |
| 7 | CORS 预检 `OPTIONS` | 200，`Allow-Headers` 含 `Authorization` |
| 8 | Knife4j/Swagger 配同样的头 | 能调通 |

### 9.10 文档侧怎么收口

- `接口设计 2.5` 已写 `Authorization: Bearer <token>` → **保持不动**；
- `技术方案 5.1` 的"Sa-Token 或 JWT"收敛为 **Sa-Token + uuid**，并注明 `timeout/active-timeout` 与 `loginId=userId`；
- 如果底座实际是 `satoken` 头且不愿改，就反过来同时改这两份文档 + 前端拦截器——**绝不允许后端一套、前端一套**。

---

> **落地顺序建议**：先做 3.1 的确认（10 分钟）→ 再定 3.5 是否加列（影响 8 张表）→ 然后写 `DataScopeSqlBuilder` + 12 条用例 → 最后做迁移脚本与页面改造。**不要先写 Handler 再补表结构**，否则返工。
