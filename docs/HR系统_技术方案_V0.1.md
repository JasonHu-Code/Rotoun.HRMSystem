# HR 人事管理系统 · 技术方案 V0.1

> 编制日期：2026-10-20
> 输入：《需求清单 V0.1.2》（v1.0 P0 80 条）、《数据库设计 V0.1》（59 表）、《接口设计 V0.1》（174 接口）、《考勤引擎设计 V0.1》、《M0 底座改造清单 V0.1》
> 适用规范：《全流程统一开发规范 V1.1》
> 状态：**已确认**（2026-10-20）。底座机制已确认：RuoYi-Vue-Plus 5.x + `PlusDataPermissionHandler`。T-01 已由《HR系统_M0底座改造清单_V0.1.md》关闭；8 张事务表快照列已落脚本并通过 MySQL 实测；可进 M0。

---

## 一、技术选型

### 1.1 选型表

| 层 | 选型 | 版本 | 依据 |
|---|---|---|---|
| 运行时 | JDK | **21 (Temurin LTS)** | 本机已装 `21.0.12.1`；RuoYi-Vue-Plus 5.x 要求 17+ |
| 框架 | Spring Boot | **3.4.x** | 与 RuoYi-Vue-Plus 5.x 对齐 |
| 底座 | **RuoYi-Vue-Plus** | 5.x | 规范 1.1「优先复用」；SRM 已在用，团队零学习成本 |
| ORM | MyBatis-Plus | 3.5.x | RuoYi 标配 |
| 数据库 | MySQL | **8.0.16+** | 用到 CHECK 约束；本机 8.0.46 已验证 |
| 缓存 | Redis | 7.x | Token、数据权限、规则解析结果 |
| 前端框架 | Vue | **3.5** | RuoYi-Vue-Plus 默认 |
| 构建 | Vite | 5.x | |
| 状态管理 | Pinia | 2.x | |
| UI 组件 | **Element Plus** | 2.8.x | 见 1.2 偏离说明 |
| 图标 | **lucide-vue-next** | 最新 | 规范 2.3 硬要求，禁 emoji |
| 图表 | ECharts | 5.x | 看板与报表 |
| 部署 | Docker Compose | — | 单机部署，见第十一节 |

**不引入**：微服务、消息队列、分库分表、ES、Flink/Spark。

理由：302 人、11 万条日结果/年、22 万条打卡流水/年。**这个量级上一套 Spring Cloud 或 MQ，运维成本会超过它解决的问题。** 单机 + 单库 + 1 个应用实例足够，真要扩容时先加缓存和索引。

### 1.2 三处偏离规范的裁定

方案先行阶段必须把冲突摊开说。以下三处与规范 V1.1 有出入，**我的判断和理由如下**，需要你认可。

#### 偏离一：UI 组件库用 Element Plus，不用 shadcn-vue

规范 2.3 要求 `shadcn-vue` + `lucide-vue-next`。但底座 RuoYi-Vue-Plus 整体基于 Element Plus（用户、角色、菜单、字典、操作日志、代码生成的页面全是 Element Plus）。

| 方案 | 代价 | 结论 |
|---|---|---|
| A. 全用 shadcn-vue | 要重写底座所有系统管理页面；团队学第二套组件库；两套主题变量对不齐 | 不选 |
| B. 全用 Element Plus | 偏离规范组件条款；视觉规范仍可满足 | **选这个** |
| C. 混用 | 样式打架、包体积多 400KB+、同一个按钮两种写法 | 坚决不选 |

**选 B 的具体含义**：

- 组件用 Element Plus
- **图标必须用 `lucide-vue-next`，禁 emoji**（规范硬要求，这条照做）
- **配色按规范：极简白蓝，主色 `#2563EB`，辅助 `#1A1A1A`**，覆盖 Element Plus 主题变量
- 间距、圆角、字重按规范执行

即：**视觉规范全遵守，只把"组件库"这一条替换为与底座一致的选择。**

#### 偏离二：审批流自研轻量状态机，不用 Flowable

RuoYi-Vue-Plus 自带 Flowable 模块。但：

- Flowable 会引入 **30+ 张表**（ACT_RE_*、ACT_RU_*、ACT_HI_*…）
- 本项目的审批场景是「入职、转正、离职、调岗、调薪、请假、加班、申诉、考勤调整」，**审批链 2 级为主，最深 3 级**
- 没有会签、没有并行网关、没有子流程、没有动态加签

用 Flowable 等于为了 10% 的功能引入 10 倍的复杂度。**用自研的 `approval_flow` + `approval_instance` 三张表足够**（已在数据库设计中）。

何时该换成 Flowable：出现"同一单据多人会签""按金额走不同分支且分支超过 3 层""需要图形化建模"。现在都不满足。

#### 偏离三：定时任务用 Spring Task + ShedLock，不用 XXL-Job

XXL-Job 需要一个独立的调度中心（另一个 Java 服务 + 一套表 + 一个管理界面）。

本项目定时任务只有 4 类：

| 任务 | 频率 |
|---|---|
| 考勤日结果增量计算 | 每日凌晨 |
| 合同/证照到期预警 | 每日 |
| 打卡数据拉取（P1） | 5–10 分钟 |
| 月结前全量重算 | 每月一次，手动触发 |

**用 `@Scheduled` + ShedLock（Redis 实现分布式锁）即可**，防止多实例重复执行。上 XXL-Job 是给不需要集群调度的系统上集群调度。

---

## 二、工程结构

### 2.1 模块划分

沿用 RuoYi-Vue-Plus 多模块骨架，**只加两个模块**，不拆细。

```
hr-system/
├── pom.xml                        父 POM
├── hr-admin/                      启动模块（含 Controller）
│   └── src/main/java/com/hr/admin/
│       ├── HrApplication.java
│       └── controller/            按域分包：org / employee / attendance / pay ...
├── hr-common/                     通用工具、常量、异常、返回体
├── hr-framework/                  底座扩展：安全、数据权限、日志、拦截器
├── hr-system/                     底座系统功能（用户/角色/菜单/字典/日志）
├── hr-biz/                        ★ 业务逻辑与持久层
│   ├── src/main/java/com/hr/biz/
│   │   ├── org/                   组织、职位、职级、任职
│   │   ├── employee/              员工主数据、子表、异动
│   │   ├── lifecycle/             入转调离、合同
│   │   ├── attendance/            考勤规则、班次、排班、打卡、日结果、单据
│   │   ├── leave/                 假期
│   │   ├── pay/                   薪酬、社保、计件
│   │   └── workflow/              审批流
│   └── src/main/resources/mapper/ 对应 XML
├── hr-attendance-engine/          ★ 考勤计算引擎（纯 Java，不依赖 Spring）
├── hr-generator/                  代码生成（底座自带）
└── hr-ui/                         前端
```

### 2.2 为什么业务只拆一个 `hr-biz`

如果按域拆成 `hr-org`、`hr-attendance`、`hr-pay` 五个 Maven 模块，会形成依赖网状：

```
attendance → employee → org
pay → attendance → employee → org
leave → employee, attendance
```

Maven 模块间循环依赖要额外抽接口层才能解，收益（编译隔离）远小于成本（改一行要动三个模块的 pom）。

**一个 `hr-biz` 模块，内部按包分层**，包之间约定依赖方向：

```
org  ← employee ← lifecycle
                      ↑
              attendance ← leave
                      ↑
                    pay
```

**只允许箭头方向依赖，反向禁止。** 靠代码评审守，不靠 Maven 强制——302 人的项目，评审比强约束更划算。

### 2.3 为什么考勤引擎单独拆模块

`hr-attendance-engine` 必须是**纯 Java，零 Spring 依赖**。

原因：26 条测试用例要能毫秒级跑完，不能起 Spring 容器。引擎的输入是内存对象（规则、班次、打卡列表、单据），输出是日结果对象，不碰数据库。

```java
// 引擎入口（示例）
public class AttendanceCalculator {
    public DayResult calc(DayContext ctx);
}

// DayContext 由 hr-biz 装配好传进来
public class DayContext {
    Employee emp;
    AttendanceRule rule;
    WorkCalendar calendar;
    Shift shift;
    List<Punch> punches;
    List<LeaveDoc> leaves;
    List<OvertimeDoc> overtimes;
    List<AppealDoc> appeals;
}
```

这样 26 条用例可以完全脱离数据库跑，也能在 CI 里每次提交都跑。

### 2.4 后端分层约定

```
controller  只做参数校验 + 调 service + 返回 {code,msg,data}
service     业务逻辑、事务边界
mapper      MyBatis-Plus，单表操作
repository  复杂查询（多表 join、统计），用 XML
```

**禁止**在 controller 里写业务逻辑，**禁止** mapper 里写业务判断。

---

## 三、依赖清单

### 3.1 后端关键依赖

| 依赖 | 版本 | 用途 |
|---|---|---|
| spring-boot-starter-web | 3.4.x | |
| spring-boot-starter-validation | 3.4.x | 参数校验 |
| spring-boot-starter-data-redis | 3.4.x | 缓存 |
| mybatis-plus-boot-starter | 3.5.x | |
| mysql-connector-j | 8.x | |
| hutool-all | 5.8.x | 工具类 |
| mapstruct | 1.6.x | DTO/VO 转换 |
| lombok | 1.18.x | |
| sa-token 或 spring-security | 按底座 | 认证 |
| shedlock-spring + shedlock-provider-redis | 5.x | 分布式定时锁 |
| easyexcel | 4.x | Excel 导入导出 |
| knife4j | 4.x | 接口文档 |

**不引入**：Flowable、XXL-Job、RocketMQ、ShardingSphere、Elasticsearch。

### 3.2 前端关键依赖

| 依赖 | 用途 |
|---|---|
| element-plus | UI 组件 |
| lucide-vue-next | 图标（规范要求） |
| echarts | 图表 |
| axios | 请求 |
| pinia | 状态 |
| vue-router | 路由 |
| dayjs | 日期处理 |

### 3.3 关键第三方风险

| 依赖 | 风险 | 应对 |
|---|---|---|
| RuoYi-Vue-Plus 5.x | 上游更新快，二次开发后难升级 | **改造点集中在 framework 与 biz，不改 common/system**；记录所有对底座的改动，便于将来合并 |
| Element Plus | 版本升级破坏性变更 | 锁定次版本，不用 latest |
| EasyExcel | 大文件内存占用 | 打卡导入用 `SXSSF` 流式读；单文件限制 5MB |

---

## 四、基础设施

### 4.1 最小部署单元

| 组件 | 规格 | 说明 |
|---|---|---|
| MySQL | 8.0，单实例 | 数据量小，不需要主从 |
| Redis | 7.x，单实例 | 缓存 + Token + 分布式锁 |
| 应用 | 1 个 Java 进程，2C4G | 302 人，单实例够 |
| Nginx | — | 静态资源 + 反向代理 |
| 文件存储 | 本地磁盘目录 | 见第十节 |

**总资源估算**：一台 4C8G 的机器可以全装下。不需要上云 RDS、不需要 Kubernetes。

### 4.2 为什么文件存储不用 MinIO

档案附件、合同扫描件、考勤导入错误文件，总量估算：

```
302 人 × 平均 5 份附件 × 2MB ≈ 3GB
+ 考勤导入错误文件（按月清理）≈ 1GB
```

**4GB 量级用 MinIO 是过度设计。** 用本地目录 + Nginx 静态服务，按 `年/月/业务类型/` 分目录。抽象一个 `FileStorage` 接口，将来要换 OSS 或 MinIO 时只换实现。

```java
public interface FileStorage {
    String upload(InputStream in, String fileName, String bizType);
    InputStream download(String path);
    void delete(String path);
    String getUrl(String path);
}
```

一期实现 `LocalFileStorage`。

---

## 五、认证与权限实现

### 5.1 认证

复用底座的 **Sa-Token + uuid** Token 机制（底座已确认 RuoYi-Vue-Plus 5.x）。**不自研认证**。

约束：
- 除 `/api/auth/login`、`/api/auth/captcha` 外全部鉴权
- Token 走 Header `Authorization: Bearer <token>`（Sa-Token 配 `token-name: Authorization` + `token-prefix: Bearer`），**禁止 URL 传参**
- **`loginId` 用 `sys_user.user_id`**（不是 `employeeId`）：纯管理员无员工档案，且离职踢下线按 `userId` 定位会话
- 有效期 8 小时（Sa-Token `timeout=28800`，`active-timeout=1800`）。**默认不是滑动续期**；若要滑动，拦截器按需 `StpUtil.renewTimeout(28800)`（每 5 分钟最多一次）
- 离职自动踢下线：`StpUtil.kickout(userId)` + 清 `hr:login:{userId}` / `hr:datascope:{userId}`
- 只读 Header（`is-read-cookie: false` / `is-read-body: false`），避免 cookie 形成第二入口

> **T-04 对齐清单见《HR系统_M0底座改造清单_V0.1.md》第九节**（配置、前端拦截器、8 条验收用例）。

### 5.2 功能权限

复用底座的 `sys_menu` + `sys_role`。前端按钮权限码由 `/api/auth/permissions` 下发，前端只做显示控制，**校验全在后端**。

### 5.3 数据权限

这是本系统与通用后台最大的差异点，要单独实现。

**规则来源**：`data_scope_rule` 表，按角色配置。

| scope_type | 含义 | 生成条件 |
|---|---|---|
| `ALL` | 全集团 | 无条件 |
| `COMPANY` | 本公司 | `legal_entity_id = ?` |
| `ORG_TREE` | 组织及子树 | `org_path like '/1/3/%'` |
| `ORG` | 本组织 | `organization_id = ?` |
| `SELF` | 仅本人 | `employee_id = ?` |

**实现方式**（MyBatis 拦截器，底座已确认走 `PlusDataPermissionHandler`）：

RuoYi-Vue-Plus 5.x 用 `DataPermissionInterceptor` + `PlusDataPermissionHandler` 生成数据权限。本系统**不注册底座 Handler**，改为注册自己的 `HrDataPermissionHandler`（同样实现 `MultiDataPermissionHandler`），注解用 `@HrDataScope`（避免与底座 `@DataPermission` 重名）。

```java
// 拦截带有 @HrDataScope 注解的 Mapper 方法，自动追加 where 条件
@HrDataScope(orgAlias = "o", empAlias = "e")
List<Employee> selectEmployeePage(EmployeeQuery q);
```

解析流程：

1. 登录时把用户所有角色的 `data_scope_rule` 合成一个 SQL 片段，存 Redis（key: `hr:datascope:{userId}`，TTL 30 分钟）
2. 多个角色取**并集**（任一角色能看到就能看到）
3. 拦截器把片段拼到 SQL 的 where 里
4. 角色权限变更时主动清 Redis

**硬约束**：

- **禁止**在业务代码写 `if (role == 'ADMIN')`。权限只从规则表读
- `can_export = 0` 的角色，导出接口直接拒绝（不只看能不能查，要看能不能拿走）
- 数据权限**必须**在 SQL 层过滤，不能查出来再在内存里筛——后者一改分页就错

> **M0 落地细节见《HR系统_M0底座改造清单_V0.1.md》**：`sys_user` 与 `organization` 的绑定链路、底座 `PlusDataPermissionHandler` 的替换方式、`sys_role.data_scope` 的三步废弃、8 张业务表补组织快照列的 ALTER、12 条数据权限验收用例。其中 3 项为本次核对新发现、技术方案原文未覆盖：① 考勤/假期/薪酬表只有 `employee_id`、缺 `organization_id`；② **已确认**底座为 `PlusDataPermissionHandler`（非 `DataScopeAspect`）；③ `data_scope_rule.scope_type` 文档写 `CUSTOM`、DDL 写 `SELF`，以 DDL 为准。

---

## 六、考勤引擎的工程组织

### 6.1 计算模式

| 模式 | 触发 | 范围 |
|---|---|---|
| 增量 | 单据审批通过 | 受影响的员工日期 |
| 全量 | 月度结算前手动触发 | 按公司 + 月份 |
| 试算 | HR 核对 | 不落库，直接返回 |

单次全量重算 9,060 条约 3–10 秒，**同步执行**，不需要异步任务框架。

### 6.2 代码结构

```
hr-attendance-engine/
├── resolver/
│   ├── RuleResolver        规则继承链解析（EMPLOYEE → TEAM → DEPT → COMPANY → GROUP）
│   ├── CalendarResolver    日历版本选取（取 max version）
│   └── ShiftResolver       班次来源（排班 → 个人绑定兜底）
├── puncher/
│   ├── PunchLoader         时间窗取数（归属日 ±12h）
│   ├── PunchDeduplicator   同分钟去重
│   └── PunchPairer         时段配对（单段/多段/跨天）
├── calculator/
│   ├── RequiredCalculator  应出勤判定（第五节矩阵）
│   ├── DurationCalculator  在岗时长、迟到早退
│   ├── AbsenceClassifier   缺勤分类（缺卡 vs 旷工）
│   └── OvertimeCalculator  加班认定（按自然日切分）
└── AttendanceCalculator    门面，组装七步流程
```

**`puncher` 和 `calculator` 必须是纯函数**——不碰数据库，不做 IO，相同输入必得相同输出。这是 26 条用例能跑的前提。

### 6.3 幂等保证

- 日结果表 `uk(employee_id, work_date)` 唯一
- 重算用 `insert ... on duplicate key update`
- 每次重算写新 `calc_batch_no`，可追溯

---

## 七、审批流实现

### 7.1 三张表的用法

```
approval_flow        流程模板（biz_type + 条件表达式）
approval_flow_node   节点（按 node_no 顺序，指定审批人类型）
approval_instance    实例（一个单据一条，记录当前节点）
```

**审批人类型**：

| 类型 | 取值方式 |
|---|---|
| `ROLE` | 按角色找（如"HR 经理"） |
| `USER` | 指定用户 ID |
| `LEADER` | 从 `position.parent_position_id` 逐级向上找在职人员 |
| `DEPT_LEADER` | 组织的 `leader_employee_id` |
| `HR` | 固定 HR 角色 |

`LEADER` 是最常用的（请假、加班走直属上级）。

### 7.2 两个必须处理的边界

**边界一：找不到审批人**

员工没有上级（如总经理）、或者上级已离职。

处理：逐级向上找，到顶还找不到，**兜底到集团 HR**，并在实例上标记 `fallback=true`。**不能因为找不到审批人就卡住流程。**

**边界二：审批期间组织调整**

申请人调岗了，原上级还要不要继续批？

处理：**按提交时的审批链快照执行**，中途不重算。理由：审批过程中换审批人，等于给了"挑审批人"的空间。

### 7.3 抄送

`HR-ATT-09` 要求申诉审批 + 抄送。实施方式：

- 单据表存 `cc_user_ids`（逗号分隔）
- 流程走完后发站内信 + 企微通知给抄送人
- 抄送人**不参与审批**，只收通知，可以在详情页看结果

---

## 八、定时任务

| 任务 | 频率 | 幂等策略 |
|---|---|---|
| 考勤日结果增量计算 | 每日 01:00 | 按 `(employee_id, work_date)` upsert |
| 合同/证照到期预警 | 每日 08:00 | 按 `(contract_id, remind_level)` upsert |
| 打卡数据拉取（P1） | 每 10 分钟 | 按 `next_id` 游标 |
| 申诉窗口到期转异常 | 每日 01:30 | 按状态机校验 |

统一用 `@Scheduled` + `@SchedulerLock`（ShedLock，Redis provider）。

**约束**：定时任务方法体内不写业务，只做"查待处理列表 → 逐条调 service"。这样手动触发和定时触发走同一段代码，不会出现两套逻辑。

---

## 九、日志与可观测

| 类型 | 方案 |
|---|---|
| 应用日志 | Logback，按天滚动，保留 30 天 |
| 操作日志 | 底座 `sys_oper_log`（谁做了什么） |
| 业务变更日志 | 自建 `biz_change_log`（哪个字段从什么变成什么） |
| 敏感数据 | **日志不得输出身份证、手机号、银行卡**。统一用 `DesensitizeUtil` 处理后再打 |
| 慢 SQL | MyBatis-Plus 自带 SQL 执行时间输出，>1s 打 WARN |
| 接口耗时 | AOP 统一记录，>2s 打 WARN |

**考勤计算日志要特殊处理**：每次重算记录 `calc_batch_no`、涉及人数、耗时。出问题时按批次号能定位到具体哪次重算改了什么。

---

## 十、部署方案

### 10.1 单机 Docker Compose

```yaml
services:
  mysql:    8.0，挂载数据卷，端口只对内
  redis:    7
  app:      Java 应用，2C4G
  nginx:    静态资源 + 反代
```

**不需要 Kubernetes**。302 人的系统上 K8s，运维成本远超收益。

### 10.2 环境划分

| 环境 | 用途 |
|---|---|
| dev | 开发本地 |
| test | 测试环境，跑全量脚本 + 造数 |
| prod | 生产 |

生产**禁用**代码生成器、Swagger 页面、SQL 日志。

### 10.3 上线前检查清单

- [ ] `rt-hrms` 库按 6 个脚本建好，跑过自检 SQL（README 第五节）
- [ ] 字典 21 项录入完毕
- [ ] 13 法人、12 职级、9 假期类型、4 班次初始化完成
- [ ] 组织树导入（业务确认版）
- [ ] 302 人导入，档案完整率 ≥ 98%
- [ ] 数据权限角色配置完毕（集团 HR / 公司 HR / 主管 / 员工）
- [ ] 默认考勤规则确认（容差 0、单位 60、补卡 3 次）
- [ ] 首月双轨验证通过

---

## 十一、开发顺序与里程碑

### 11.1 顺序

按**依赖倒序**排，每一阶段结束时都有可演示的东西。

| 阶段 | 内容 | 交付 |
|---|---|---|
| **M0 基建** | 工程骨架、数据库、认证、数据权限、日志、异常处理 | 能登录、能看菜单、权限生效 |
| **M1 组织与职位** | 法人、组织树、职级（12 级）、职位库、任职 | 能看到完整组织树和组织架构图 |
| **M2 员工** | 主档、6 张子表、导入导出、异动历史 | 302 人可录入、可查询、可导入 |
| **M3 考勤配置** | 规则、班次、日历、排班 | 能配规则、能排一个月班 |
| **M4 考勤计算** | 打卡导入、日结果、异常、申诉、加班、月结 | **跑通 30 条测试用例** |
| **M5 假期** | 类型、额度、请假单、调休 | 请假能提、余额能扣 |
| **M6 薪酬** | 项目、方案、薪档、试算、封账、工资条 | 能试算一个月 |
| **M7 报表与自助** | 看板、考勤报表、员工自助 | 可上线 |

M0–M2 是地基，M3–M4 是本项目最难的部分（考勤），建议 M4 单独排时间。

### 11.2 为什么考勤排在第 4 阶段而不是最后

考勤依赖员工和组织（M1/M2），但它自己最复杂、最容易返工。**放在 M4，留出后面 3 个阶段的时间吸收它的影响**。如果把考勤放最后，一旦算法实现和预期不符，薪酬（M6）会跟着返工。

### 11.3 与业务交付物的并行关系

| 业务交付物 | 最晚需要时间 |
|---|---|
| 职级标准表定稿 | M1 开始前（但表结构不依赖它，可先用 12 级初稿） |
| 职位清单 | M2 结束前 |
| 全员定级表 | M2 结束前 |
| 近 3 个月工资明细 | **M6 开始前** |

**M0–M2 完全可以先开工**，因为组织、员工主数据的表结构不依赖具体级数和职位条数。这也是我之前建议"先设计按标准来、后续再调"的原因。

---

## 十二、风险与应对

| # | 风险 | 影响 | 应对 |
|---|---|---|---|
| 1 | 考勤算法实现与 26 条用例不符 | 返工，影响薪酬 | M4 独立阶段；用例先写；纯函数便于单测 |
| 2 | 职级标准迟迟不定稿 | M2 卡住 | 先用 12 级初稿推进，表结构支持任意级数 |
| 3 | 薪资数据始终拿不到 | 薪酬模块空跑 | 结构照做；到 M6 仍无数据则顺延 P1 |
| 4 | 302 人数据质量差，导入反复 | 上线延期 | 导入前预校验 + 错误行回显；准备两轮演练 |
| 5 | RuoYi 底座二次开发后难升级 | 长期维护成本 | 改造点集中在 framework/biz；记录 diff |
| 6 | 多品牌考勤机（P1）对接工作量超预期 | P1 延期 | P1 独立评估，不影响 v1.0 |
| 7 | 组织/职位被业务反复调整 | 数据返工 | 组织变更走单据 + 留版本；不直接改库 |

---

## 十三、待你拍板

| # | 事项 | 我的建议 |
|---|---|---|
| 1 | 前端组件库用 Element Plus（偏离规范的 shadcn-vue） | **接受**。视觉规范全遵守，只换组件库，理由是底座决定 |
| 2 | 审批流自研轻量状态机，不用 Flowable | **接受**。2 级审批用 Flowable 是 10 倍复杂度换 10% 功能 |
| 3 | 定时任务用 Spring Task + ShedLock，不用 XXL-Job | **接受**。4 个任务不值得部署调度中心 |
| 4 | 文件存本地磁盘，不用 MinIO | **接受**。4GB 量级，抽象接口留切换余地 |
| 5 | 业务只拆一个 `hr-biz` 模块，不按域拆 5 个 | **接受**。避免 Maven 循环依赖 |
| 6 | 考勤引擎单独成模块，纯 Java 无 Spring | **接受**。26 条用例要能在 CI 里毫秒级跑 |
| 7 | 单机部署，不上 K8s | **接受**。302 人 |

---

## 十四、下一步

技术方案确认后，M0 的产出是：

1. 创建工程骨架（RuoYi-Vue-Plus 5.x + 两个新模块）
2. 执行 6 个建表脚本
3. 打通认证、菜单、数据权限
4. 一个"能登录进来看见组织树"的最小闭环

**M0 的目标不是功能，是证明"这套底座 + 这套改造方式"跑得通。** 跑通了，后面 6 个阶段都是往里填业务。
