# Rotoun HRMS · 瑞堂人事管理系统

单仓（monorepo）：**后端 + 前端 + 建库脚本 + 设计文档**放在同一个仓库。

## 技术栈（2026-10-20 实际核对）

| 层 | 版本 |
|---|---|
| 后端底座 | RuoYi-Vue-Plus **5.6.2**（分支 5.X） |
| Spring Boot | **3.5.16** |
| JDK | 17（本机 JDK 21 兼容，脚手架 `java.version=17`） |
| MyBatis-Plus | **3.5.16** |
| 认证 | **Sa-Token + JWT**（`StpLogicJwtForSimple` + `PlusSaTokenDao`） |
| 缓存 / 分布式锁 | Redis 7 + Redisson 3.52 |
| 工作流 | Warm-Flow 1.8.9（底座自带；v1.0 计划不启用，**待拍板**） |
| 任务调度 | SnailJob 1.10（底座自带；v1.0 计划不启用，**待拍板**） |
| 前端 | plus-ui **5.X**（5.6.2-2.6.2） |
| Vue / Element Plus / Vite | 3.5.30 / 2.13.5 / 7.3.2 |
| Node / pnpm | >= 20.19 / 10.x |
| 数据库 | MySQL 8.0.16+，库名 **`rt-hrms`** |

## 已做的项目化改动（相对上游脚手架）

| # | 改动 | 文件 |
|---|---|---|
| 1 | 数据源 `ry-vue` → `rt-hrms` | `backend/ruoyi-admin/src/main/resources/application-dev.yml` |
| 2 | Sa-Token 补 `timeout: 28800`、`active-timeout: 1800`、`is-read-body: false` | 同目录 `application.yml` |
| 3 | 前端标题/Logo 改为「瑞堂人事管理系统 / Rotoun HRMS」 | `frontend/.env.development` / `.env.production` |
| 4 | 前端包名改为 `rotoun-hrms-ui` | `frontend/package.json` |
| 5 | 移除布局页的 WebSocket/SSE 初始化（token 曾拼在 URL 上，违反规范 7.4） | `frontend/src/layout/index.vue` |
| 6 | 移除 `ruoyi-job` / `ruoyi-workflow` 模块与 admin 依赖（不启用 SnailJob / Warm-Flow） | `backend/pom.xml`、`ruoyi-admin/pom.xml`、`ruoyi-modules/pom.xml` |
| 7 | 移除 `ruoyi-snailjob-server`；新增 ShedLock 7.10.1 + `ShedLockConfig` | `ruoyi-extend/pom.xml`、`web/config/ShedLockConfig.java` |
| 8 | 补 `db/00_ruoyi_base.sql`（底座 25 张表，已移除 SnailJob 菜单） | `db/00_ruoyi_base.sql` |
| 9 | 关闭底座多租户（HR 单租户，多组织靠 `organization` + 数据权限） | `application.yml` 的 `tenant.enable: false` |

## 已确认的技术取舍（2026-10-20）

| # | 事项 | 结论 |
|---|---|---|
| 1 | 审批流 | **自研 `approval_flow` + `approval_flow_node` + `approval_instance` 三张表**，不启用 Warm-Flow 1.8.9 |
| 2 | 定时任务 | **Spring Task + ShedLock 7.10.1**（Redis provider），不启用 SnailJob 1.10 |

落地情况：`ruoyi-job` / `ruoyi-workflow` / `ruoyi-snailjob-server` 已从 Maven reactor 与 `ruoyi-admin` 依赖移除；`warm-flow` 配置与 SpringDoc 工作流分组已清理；新增 `ShedLockConfig`（`@EnableScheduling` + `@EnableSchedulerLock`）。

## 目录结构

```
Rotoun.HRMSystem/
├── backend/            # RuoYi-Vue-Plus 5.6.2 后端（Maven 多模块）
│   ├── ruoyi-admin/    # 启动模块
│   ├── ruoyi-common/   # 公共组件（含 common-satoken）
│   ├── ruoyi-modules/  # 业务模块
│   ├── ruoyi-extend/   # 扩展
│   └── script/         # 上游脚本
├── frontend/           # plus-ui 5.X 前端（Vue3 + TS + Element Plus）
├── db/                 # MySQL 脚本：00 底座表 + 01~06 业务表（按序执行）
├── docs/               # 需求、技术方案、数据库设计、M0 改造清单、接口、考勤引擎
├── .gitignore
└── README.md
```

> 当前是 **M0 前的骨架**。业务模块 `hr-biz`、`hr-attendance-engine` 与组织/员工/考勤等代码尚未加入，按《M0 底座改造清单》逐步落地。

## 本地启动

### 1. 建库

```sql
CREATE DATABASE `rt-hrms` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
```

### 2. 执行脚本（按序）

```bash
cd db
# 必须先跑底座表（sys_user / sys_role / sys_menu / sys_dict_* ...）
mysql -h127.0.0.1 -P3306 -uroot -p --default-character-set=utf8mb4 rt-hrms < 00_ruoyi_base.sql

# 再跑业务表
for f in 01_schema_org.sql 02_schema_employee.sql 03_schema_attendance.sql \
         04_schema_pay_leave.sql 05_schema_system.sql 06_init_data.sql; do
  mysql -h127.0.0.1 -P3306 -uroot -p --default-character-set=utf8mb4 rt-hrms < "$f"
done
```

> **必须带 `--default-character-set=utf8mb4`**，否则基础 SQL 里的中文会按 latin1 解析，报 `Data too long for column 'contact_user_name'`。
>
> **不要执行** `backend/script/sql/ry_job.sql` 和 `ry_workflow.sql`：本项目已决定不启用 SnailJob / Warm-Flow。
>
> 全量执行后应为 **84 张表**（底座 25 + 业务 59）、`sys_user` 3 条、`sys_menu` 120 条、法人 13、职级 12。

### 3. 改数据源

`backend/ruoyi-admin/src/main/resources/application-dev.yml`：

```yaml
url: jdbc:mysql://localhost:3306/rt-hrms?...
username: root
password: root   # 按本机实际密码改
```

### 4. 启动后端

```bash
cd backend
mvn clean package -DskipTests
# 运行 org.dromara.DromaraApplication
# 或 java -jar ruoyi-admin/target/ruoyi-admin.jar
```

默认端口 `8080`。

### 5. 启动前端

```bash
cd frontend
pnpm install
pnpm dev
```

默认端口 `80`（见 `.env.development` 的 `VITE_APP_PORT`；Windows 下 80 可能需管理员权限，可改为 8081）。

## 认证配置（已对齐）

| 配置 | 位置 | 值 |
|---|---|---|
| token 名 | `application.yml` | `token-name: Authorization` |
| token 前缀 | `ruoyi-common-satoken/src/main/resources/common-satoken.yml` | `token-prefix: "Bearer"` |
| 有效期 | `application.yml` | `timeout: 28800`（8 小时） |
| 无操作冻结 | `application.yml` | `active-timeout: 1800`（30 分钟） |
| 禁止 URL 传参 | `application.yml` | `is-read-body: false` |
| 认证模式 | `SaTokenConfig.java` | `StpLogicJwtForSimple` + `PlusSaTokenDao`（Redis） |

前端 `src/utils/request.ts` 发送 `Authorization: Bearer <token>`，与后端一致。

**M0 必须改**：`loginId` 用 `sys_user.user_id`（不是 employeeId），否则纯管理员无法登录、离职踢下线定位不到会话。详见 `docs/HR系统_M0底座改造清单_V0.1.md` 第九节。

## 数据库约定

- 库名 `rt-hrms`，表名无业务前缀（`organization` / `attendance_rule` 等）
- 无物理外键；统一 `id / is_deleted / create_at / update_at`
- 8 张事务表含 `organization_id` + `legal_entity_id` 快照列：`attendance_day_result`、`attendance_exception`、`attendance_appeal`、`overtime_apply`、`leave_quota`、`leave_apply`、`salary_detail`、`piece_output`
- 数据权限不用 `sys_dept`，自建 `organization`，规则走 `data_scope_rule`

## 设计文档

| 文档 | 内容 |
|---|---|
| `docs/HR人事管理系统_需求清单_V0.1.2.md` | 需求基线，241 条（P0 80 / P1 132 / P2 29） |
| `docs/HR系统_技术方案_V0.1.md` | 选型、工程结构、M0–M7、三处规范偏离 |
| `docs/HR系统_数据库设计_V0.1.md` | 59 张表字段级设计 |
| `docs/HR系统_M0底座改造清单_V0.1.md` | 数据权限改造、Token 对齐、验收用例 |
| `docs/HR系统_接口设计_V0.1.md` | 174 个接口、错误码 |
| `docs/HR系统_考勤计算引擎设计_V0.1.md` | 七步算法、边界场景 |

## 上游与许可

- 后端：[dromara/RuoYi-Vue-Plus](https://github.com/dromara/RuoYi-Vue-Plus) 5.X，MIT
- 前端：[JavaLionLi/plus-ui](https://github.com/JavaLionLi/plus-ui) 5.X，MIT

二次开发遵循《全流程统一开发规范 V1.1》；上游 LICENSE 保留在各子目录。
