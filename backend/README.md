# Rotoun HRMS · 后端

基于 **RuoYi-Vue-Plus 5.6.2**（MIT License）二次开发。

| 项 | 版本 |
|---|---|
| Spring Boot | 3.5.16 |
| JDK | 17+（本机 21） |
| MyBatis-Plus | 3.5.16 |
| 认证 | Sa-Token + JWT（`Authorization: Bearer <token>`） |
| 数据库 | MySQL 8 · `rt-hrms` |
| 定时任务 | Spring Task + ShedLock（不启用 SnailJob） |
| 审批流 | 自研 `approval_flow` 三张表（不启用 Warm-Flow） |

## 启动

```bash
# 1. 建库并执行 db/00~06（见仓库根 README）
# 2. 改 rotoun-admin/src/main/resources/application-dev.yml 的数据源账号密码
mvn clean package -DskipTests

# 3. 运行启动类
#    org.dromara.DromaraApplication
```

默认端口 `8080`。

## 模块

```
rotoun-admin/     启动模块（Controller、配置）
rotoun-common/    公共组件（含 common-satoken、common-mybatis）
rotoun-modules/   业务模块（system / generator / demo）
rotoun-extend/    扩展（monitor-admin）
script/           上游脚本（docker、sql 参考）
```

业务模块 `hr-biz`、`hr-attendance-engine` 尚未加入，按《M0 底座改造清单》逐步落地。
