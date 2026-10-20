# HR 人事管理系统 · 接口设计 V0.1

> 编制日期：2026-10-19
> 输入：《HR人事管理系统_需求清单_V0.1.1》（P0 80 条）、《HR系统_数据库设计_V0.1》（59 张表）
> 适用规范：《全流程统一开发规范 V1.1》第五章（API 接口开发规范）
> 状态：**待评审**

---

## 一、两套接口风格并存（重要）

复用 RuoYi-Vue-Plus 底座，会同时存在两套路径风格。**不做统一改造**，因为改造底座意味着以后每次升级 RuoYi 都要重新改一遍。

| 类别 | 前缀 | 风格 | 示例 | 处理 |
|---|---|---|---|---|
| **业务接口**（本系统开发） | `/api` | 小写横线，符合规范 5.1 | `/api/employee/page` | 全部按规范写 |
| **底座接口**（RuoYi 自带） | `/system`、`/monitor` 等 | RuoYi 原生 | `/system/user/list` | **保持原样** |

前端只需记一条规则：**调用本系统的业务接口，一律走 `/api`；调用登录、菜单、角色、字典这些底座功能，走原路径。**

---

## 二、统一约定

### 2.1 统一返回体（规范 5.2，强制）

```json
{
  "code": 200,
  "msg": "success",
  "data": {}
}
```

- 成功固定 `code = 200`
- **`data` 字段禁止省略**。无返回内容时给 `null` 或 `{}`，不能整个字段消失
- 业务失败也返回 HTTP 200，靠 `code` 区分（RuoYi 惯例；`code != 200` 时前端统一拦截提示）

### 2.2 分页

请求固定参数：`pageNum`、`pageSize`（默认 1 / 10）。

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "total": 302,
    "pageNum": 1,
    "pageSize": 10,
    "rows": []
  }
}
```

### 2.3 参数位置（规范 5.3）

| 方法 | 参数位置 |
|---|---|
| GET | Query |
| POST / PUT / PATCH | JSON Body |
| 文件上传 | multipart/form-data |

前端参数小驼峰；**后端全量校验，永不信任前端**。

### 2.4 路由规则（规范 5.1）

- 全小写 + 横线分隔
- GET 查询 / POST 新增 / PUT 全量更新 / PATCH 局部更新 / DELETE 删除
- 例外：`POST /api/xxx/page` 用于「复杂条件分页查询」——查询条件太多放不进 URL，这是业务系统常态，也是 RuoYi 惯例

### 2.5 鉴权

- Token 走 Header：`Authorization: Bearer <token>`，**禁止 URL 传参**（规范 7.4）
- 除 `/api/auth/login` 外，所有接口必须鉴权，**禁裸接口**
- 数据权限由后端按 `data_scope_rule` 自动拼条件，前端不传组织范围

### 2.6 幂等

| 场景 | 方案 |
|---|---|
| 新增类接口 | 前端传 `requestId`（UUID），后端 5 分钟内相同 `requestId` 直接返回上次结果 |
| 导入类接口 | 文件 SHA-256 去重，同一文件重复导入直接拒绝并告警 |
| 审批类接口 | 按 `instanceId + nodeNo` 做状态机校验，重复提交返回当前状态 |

### 2.7 时间与金额格式

- 日期：`yyyy-MM-dd`
- 时间：`yyyy-MM-dd HH:mm:ss`
- 月份：`yyyy-MM`
- 金额：字符串传输（避免 JS 浮点精度问题），如 `"12500.00"`
- 比例：小数，如 `0.1500` 表示 15%

---

## 三、错误码设计

### 3.1 HTTP 层

| 码 | 含义 |
|---|---|
| 200 | 成功（业务失败也返回 200，看 `code`） |
| 401 | Token 无效或过期 |
| 403 | 无访问权限 |
| 404 | 路径不存在 |

### 3.2 业务码分段

| 段 | 域 | 示例 |
|---|---|---|
| 10000–10999 | 认证与账号 | `10001` 用户名或密码错误 |
| 11000–11999 | 组织与职位 | `11001` 组织下存在在职员工，不能删除 |
| 12000–12999 | 员工主数据 | `12001` 身份证号已存在 |
| 13000–13999 | 入转调离与合同 | `13001` 试用期超过法定上限 |
| 14000–14999 | 考勤与排班 | `14001` 该月考勤已锁定 |
| 15000–15999 | 假期 | `15001` 假期余额不足 |
| 16000–16999 | 薪酬 | `16001` 该批次已封账 |
| 17000–17999 | 社保 | `17001` 参保方案不存在 |
| 18000–18999 | 审批与权限 | `18001` 无审批权限 |
| 19000–19999 | 系统 | `19001` 字典值不存在 |

### 3.3 关键业务码清单

| 码 | msg |
|---|---|
| 11001 | 该组织下存在在职员工，不能删除 |
| 11002 | 该职级已被 N 名员工引用，只能停用不能删除 |
| 11003 | 该职位下存在在职人员，不能停用 |
| 12001 | 身份证号已存在（工号 XXX） |
| 12002 | 工号已存在 |
| 12003 | 员工状态不允许此操作 |
| 13001 | 试用期超过法定上限（合同期 X 年，试用期不得超过 Y 个月） |
| 13002 | 该员工已有生效中的劳动合同 |
| 13003 | 连续两次固定期限合同，应签订无固定期限 |
| 14001 | 该月考勤已锁定，请走考勤调整单 |
| 14002 | 该员工该日已有排班，请走改班单 |
| 14003 | 规则作用域与已存在规则冲突（同版本重复） |
| 14004 | 导入文件与历史批次重复 |
| 14005 | 打卡记录时间格式无法识别 |
| 15001 | 假期余额不足（剩余 X 天） |
| 15002 | 请假时段与已有请假单重叠 |
| 16001 | 该薪资批次已封账，不能修改 |
| 16002 | 未提供该月薪资标准，无法计算 |
| 18001 | 无审批权限 |
| 18002 | 该单据已处理，请勿重复提交 |

---

## 四、认证（`/api/auth`）

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/auth/login` | 登录，返回 token | HR-SYS-06 |
| POST | `/api/auth/logout` | 登出 | HR-SYS-06 |
| GET | `/api/auth/user-info` | 当前用户信息 + 数据权限范围 | HR-SYS-01 |
| GET | `/api/auth/menus` | 当前用户菜单树 | HR-SYS-02 |
| GET | `/api/auth/permissions` | 按钮级权限码 | HR-SYS-02 |

> 登录失败次数限制、验证码走 RuoYi 底座能力，不重复实现（规范 1.1）。

---

## 五、组织与职位（`/api`）

### 5.1 法人

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/legal-entity/list` | 法人列表（下拉用） | ORG-01 |
| GET | `/api/legal-entity/{id}` | 法人详情 | ORG-01 |
| POST | `/api/legal-entity` | 新增法人 | ORG-01 |
| PUT | `/api/legal-entity/{id}` | 修改法人 | ORG-01 |

### 5.2 组织

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/organization/tree` | 组织树（按法人过滤） | ORG-02 |
| GET | `/api/organization/list` | 组织列表（扁平） | ORG-02 |
| GET | `/api/organization/{id}` | 组织详情 | ORG-02 |
| POST | `/api/organization` | 新增组织 | ORG-02 |
| PUT | `/api/organization/{id}` | 修改组织 | ORG-02 |
| DELETE | `/api/organization/{id}` | 停用组织（逻辑） | ORG-02 |
| GET | `/api/organization/{id}/history` | 组织变更历史 | ORG-04 |
| POST | `/api/organization/change` | 组织变更单（含受控文件版本） | ORG-15、ORG-14 |
| POST | `/api/organization/{id}/merge` | 组织合并 | ORG-09 |

### 5.3 职级

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/position-grade/list` | 职级列表 | ORG-11 |
| POST | `/api/position-grade` | 新增职级 | ORG-18 |
| PUT | `/api/position-grade/{id}` | 修改职级（返回影响人数） | ORG-18 |
| PATCH | `/api/position-grade/{id}/status` | 启用 / 停用 | ORG-18 |
| DELETE | `/api/position-grade/{id}` | 删除（**被引用时拒绝**） | ORG-18 |
| GET | `/api/position-grade/{id}/impact` | 影响人数预览 | ORG-18 |

### 5.4 公司职级映射

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/company-grade-relation/list` | 按法人查映射 | ORG-12 |
| POST | `/api/company-grade-relation/batch` | 批量保存映射 | ORG-12 |

### 5.5 职位

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/position/page` | 职位分页 | ORG-05 |
| GET | `/api/position/tree` | 职位汇报树 | ORG-07 |
| GET | `/api/position/{id}` | 职位详情 | ORG-05 |
| POST | `/api/position` | 新增职位 | ORG-05 |
| PUT | `/api/position/{id}` | 修改职位 | ORG-05 |
| DELETE | `/api/position/{id}` | 停用职位（有在职人员时拒绝） | ORG-05 |
| GET | `/api/position/{id}/employees` | 该职位在岗人员 | ORG-05 |
| POST | `/api/position/import` | 批量导入职位 | ORG-17 |
| GET | `/api/position/export` | 导出职位清单 | ORG-17 |

---

## 六、员工（`/api`）

### 6.1 主档

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/employee/page` | 员工分页（复杂条件） | EMP-01 |
| GET | `/api/employee/{id}` | 员工详情 | EMP-02 |
| GET | `/api/employee/{id}/full` | 聚合详情（主档+任职+子表） | EMP-02 |
| POST | `/api/employee` | 新增员工 | EMP-01 |
| PUT | `/api/employee/{id}` | 修改员工 | EMP-02 |
| DELETE | `/api/employee/{id}` | 逻辑删除 | EMP-01 |
| PATCH | `/api/employee/{id}/status` | 变更员工状态 | EMP-11 |
| GET | `/api/employee/{id}/change-history` | 异动历史 | EMP-12 |
| POST | `/api/employee/check-id-card` | 身份证查重（**必须 POST，禁止 GET 传证件号**，见 6.4） | EMP-03 |
| GET | `/api/employee/next-emp-no` | 生成下一个工号 | EMP-13 |
| POST | `/api/employee/import` | 批量导入（预校验+错误行回显） | EMP-16 |
| GET | `/api/employee/import-template` | 下载导入模板 | EMP-16 |
| GET | `/api/employee/export` | 导出 | EMP-16 |

### 6.4 身份证查重必须用 POST（安全约束）

**禁止**写成 `GET /api/employee/check-id-card?no=513029…`。原因：URL 会进 Nginx access log、浏览器历史、Referer，身份证号属于最高级别敏感数据，违反规范 7.5「日志不输出敏感数据」。

```
POST /api/employee/check-id-card
Body: { "idCardNo": "51302919780912273X" }
```

响应**只返回是否存在，不回显他人信息**：

```json
{ "code": 200, "msg": "success", "data": { "exists": true, "empNo": "AH2***057" } }
```

工号也要脱敏。否则这个接口等于一个"按身份证反查员工"的查询服务。

> 同理：`POST /api/salary-detail/payslip`（工资条）也不用 GET。虽然参数不含证件号，但"某人某月的工资条"本身就是敏感信息，不宜留在 URL 里。

### 6.2 子表（统一样式）

以下 6 张子表统一四组接口，路径规则 `/api/employee/{employeeId}/{resource}`：

| 资源 | 说明 | 需求 |
|---|---|---|
| `education` | 教育经历 | EMP-05 |
| `work-experience` | 工作经历 | EMP-06 |
| `family` | 家庭成员 | EMP-07 |
| `bank-account` | 银行卡 | EMP-08 |
| `certificate` | 证照 | EMP-09 |
| `attachment` | 附件 | EMP-10 |

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/api/employee/{employeeId}/{resource}/list` | 列表 |
| POST | `/api/employee/{employeeId}/{resource}` | 新增 |
| PUT | `/api/employee/{employeeId}/{resource}/{id}` | 修改 |
| DELETE | `/api/employee/{employeeId}/{resource}/{id}` | 删除 |

### 6.3 证照预警

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/employee-certificate/expiring` | 到期证照清单（90 天内） | EMP-09 |

---

## 七、入转调离与合同（`/api`）

### 7.1 三张单据（统一模式）

| 资源 | 路径 | 需求 |
|---|---|---|
| 入职 | `/api/onboard-order` | LCM-01 |
| 转正 | `/api/regular-order` | LCM-03/04 |
| 离职 | `/api/resign-order` | LCM-09 |

每张单据四组接口：

| 方法 | 路径 | 用途 |
|---|---|---|
| POST | `/api/{resource}/page` | 分页 |
| POST | `/api/{resource}` | 新建单据 |
| PUT | `/api/{resource}/{id}` | 修改（仅草稿态） |
| POST | `/api/{resource}/{id}/submit` | 提交审批 |
| GET | `/api/{resource}/{id}` | 详情 |

### 7.2 调岗调薪

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/employee/{id}/transfer` | 调岗（跨法人/跨组织） | LCM-05 |
| POST | `/api/employee/{id}/salary-adjust` | 调薪 | LCM-06 |
| POST | `/api/employee/{id}/dispatch` | 借调/外派 | LCM-07 |

### 7.3 合同

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/labor-contract/page` | 合同分页 | CON-01 |
| POST | `/api/labor-contract` | 签订合同 | CON-01 |
| PUT | `/api/labor-contract/{id}` | 修改合同 | CON-01 |
| GET | `/api/labor-contract/expiring` | 到期清单（30/60/90 天） | CON-03 |
| GET | `/api/labor-contract/renew-check` | 续签次数校验 | CON-04 |
| POST | `/api/labor-contract/{id}/renew` | 续签 | CON-04 |
| POST | `/api/labor-contract/{id}/terminate` | 解除 | CON-06 |

---

## 八、考勤（`/api`）— 接口最多、最需要仔细定

### 8.1 考勤规则

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/attendance-rule/page` | 规则分页 | ATT-18 |
| POST | `/api/attendance-rule` | 新增规则 | ATT-18 |
| PUT | `/api/attendance-rule/{id}` | 修改规则（自动升版本） | ATT-17 |
| PATCH | `/api/attendance-rule/{id}/status` | 启停 | ATT-18 |
| GET | `/api/attendance-rule/resolve` | **规则解析预览**（传员工+日期，返回命中哪条及继承路径） | ATT-19 |

**规则版本约定（必须遵守）**

1. **`ruleVersion` 不接受前端传值**。新建时后端按 `max(rule_version)+1`（同 `scope_type + scope_id` 内）自动生成。
2. **规则不可就地修改**。`PUT /api/attendance-rule/{id}` 的实际语义是"基于此版本新建下一版 + 停用旧版本"，响应返回新的 `ruleVersion`。
3. 为什么：日结果存的是 `rule_version` 快照。如果允许就地改，历史考勤结果指向的版本内容变了，"当时按什么规则算的"就永远查不清。
4. 唯一约束是 `(scope_type, scope_id, rule_version, effective_from)` —— **同一版本号可以对应多个生效区间**。这是为春节等特殊排班准备的：HR 会提前配"春节常白班"和"平时两班倒"两条，版本号可以相同，靠生效日期区分。

### 8.2 班次

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/shift/list` | 班次列表 | ATT-01 |
| GET | `/api/shift/{id}` | 班次详情（含时段） | ATT-01 |
| POST | `/api/shift` | 新增班次（含时段） | ATT-01 |
| PUT | `/api/shift/{id}` | 修改班次 | ATT-01 |
| DELETE | `/api/shift/{id}` | 停用班次 | ATT-01 |

### 8.3 个人班次与日历

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/employee-shift-binding/page` | 个人班次分页 | ATT-20 |
| POST | `/api/employee-shift-binding` | 新增（须选原因类型） | ATT-20 |
| DELETE | `/api/employee-shift-binding/{id}` | 终止绑定 | ATT-20 |
| GET | `/api/work-calendar/{legalEntityId}/{year}` | 年度日历 | ATT-04 |
| POST | `/api/work-calendar/batch-save` | 批量维护日历 | ATT-04 |
| POST | `/api/work-calendar/copy-year` | 年度复制（含法定假调整） | ATT-04 |
| POST | `/api/work-calendar/override` | 个人日历覆盖（**只允许安排上班**） | ATT-04、ATT-24 |
| DELETE | `/api/work-calendar/override/{id}` | 撤销覆盖 | ATT-24 |

### 8.4 排班

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/shift-schedule/calendar` | 排班表视图（按组织+月份） | ATT-03 |
| POST | `/api/shift-schedule/batch` | 批量排班 | ATT-03 |
| POST | `/api/shift-schedule/rotation` | **轮班自动生成**（按班制周期） | ATT-02 |
| POST | `/api/shift-schedule/change` | 改班单（单人单日） | ATT-03 |
| POST | `/api/shift-schedule/copy` | 从上月复制 | ATT-03 |

### 8.5 打卡数据

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/attendance-punch/import` | **文件导入**（v1.0 唯一入口） | ATT-29 |
| GET | `/api/attendance-punch/import-template` | 下载导入模板 | ATT-29 |
| POST | `/api/attendance-punch/import-batch/page` | 导入批次列表 | ATT-29 |
| GET | `/api/attendance-punch/import-batch/{id}/errors` | 错误行明细 | ATT-29 |
| POST | `/api/attendance-punch/page` | 打卡流水查询 | ATT-05 |
| POST | `/api/attendance-punch/unclaimed/page` | 未认领流水 | ATT-29 |
| POST | `/api/attendance-punch/{id}/claim` | 认领（绑定工号） | ATT-29 |
| GET | `/api/device-user-relation/list` | 设备用户号映射 | ATT-29 |
| POST | `/api/device-user-relation/batch` | 批量维护映射 | ATT-29 |
| POST | `/api/device-user-relation/import` | 映射表导入 | ATT-29 |

### 8.6 考勤结果

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/attendance-day-result/page` | 日结果分页（按人/组织/日期） | ATT-07 |
| GET | `/api/attendance-day-result/detail` | **单日明细（含计算依据）** | ATT-28 |
| POST | `/api/attendance-day-result/recalc` | **重算（按人/按组织/按月）** | ATT-07 |
| GET | `/api/attendance-day-result/statistics` | 考勤统计 | ATT-14 |
| GET | `/api/attendance-day-result/export` | 导出 | ATT-14 |
| POST | `/api/attendance-month-close/close` | 月度结算锁定 | ATT-13 |
| POST | `/api/attendance-month-close/reopen` | 反锁定（需审批） | ATT-13 |
| GET | `/api/attendance-month-close/status` | 结算状态 | ATT-13 |

### 8.7 异常、申诉、加班

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/attendance-exception/page` | 异常台账 | ATT-08 |
| POST | `/api/attendance-exception/{id}/handle` | 处理异常 | ATT-08 |
| POST | `/api/attendance-appeal/page` | 申诉列表 | ATT-09 |
| POST | `/api/attendance-appeal` | 提交申诉/补卡 | ATT-09 |
| POST | `/api/attendance-appeal/{id}/submit` | 提交审批 | ATT-09 |
| POST | `/api/overtime-apply/page` | 加班单列表 | ATT-10 |
| POST | `/api/overtime-apply` | 提交加班单 | ATT-10 |
| POST | `/api/overtime-apply/{id}/submit` | 提交审批 | ATT-10 |
| POST | `/api/attendance-adjust-order` | 考勤调整单（锁定后） | ATT-13 |

---

## 九、假期（`/api`）

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/leave-type/list` | 假期类型 | LEA-01 |
| POST | `/api/leave-type` | 新增类型 | LEA-01 |
| PUT | `/api/leave-type/{id}` | 修改类型 | LEA-01 |
| GET | `/api/leave-quota/balance` | 某员工年度余额 | LEA-05 |
| POST | `/api/leave-quota/page` | 额度分页 | LEA-06 |
| POST | `/api/leave-quota/grant` | 年度批量发放 | LEA-02 |
| POST | `/api/leave-quota/adjust` | 手工调整 | LEA-06 |
| GET | `/api/leave-quota/{employeeId}/log` | 额度流水 | LEA-06 |
| POST | `/api/leave-apply/page` | 请假单列表 | LEA-04 |
| POST | `/api/leave-apply` | 提交请假（**前置余额校验**） | LEA-04/05 |
| POST | `/api/leave-apply/{id}/submit` | 提交审批 | LEA-04 |

---

## 十、薪酬与社保（`/api`）

### 10.1 薪资配置

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/salary-item/list` | 薪资项目 | PAY-01 |
| POST | `/api/salary-item` | 新增项目 | PAY-01 |
| PUT | `/api/salary-item/{id}` | 修改项目 | PAY-01 |
| GET | `/api/salary-plan/list` | 薪资方案 | PAY-03 |
| POST | `/api/salary-plan` | 新增方案 | PAY-03 |
| PUT | `/api/salary-plan/{id}` | 修改方案 | PAY-03 |
| GET | `/api/salary-plan/{id}/items` | 方案项目 | PAY-03 |
| POST | `/api/salary-plan/{id}/items` | 保存方案项目 | PAY-03 |
| GET | `/api/grade-salary-standard/list` | 职级薪档 | PAY-02 |
| POST | `/api/grade-salary-standard/batch` | 批量维护薪档 | PAY-02 |

### 10.2 计件

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/piece-rate/page` | 工序单价分页 | PAY-06 |
| POST | `/api/piece-rate` | 新增单价 | PAY-06 |
| PUT | `/api/piece-rate/{id}` | 修改单价（带生效日期） | PAY-06 |
| POST | `/api/piece-output/page` | 产量记录 | PAY-05 |
| POST | `/api/piece-output/batch` | 批量录入产量 | PAY-05 |
| POST | `/api/piece-output/import` | 导入产量 | PAY-05 |

### 10.3 算薪

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| POST | `/api/salary-calc/preview` | **试算（不落正式数据）** | PAY-13 |
| POST | `/api/salary-calc/confirm` | 封账 | PAY-14 |
| POST | `/api/salary-detail/page` | 薪资明细分页 | PAY-15 |
| GET | `/api/salary-detail/{id}` | 明细详情（含项目行） | PAY-15 |
| GET | `/api/salary-detail/export` | 导出 | PAY-15 |
| POST | `/api/salary-detail/payslip` | 工资条（**POST，需二次验证**） | PAY-15、SYS-08 |

### 10.4 社保

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/social-insurance-plan/list` | 社保方案 | BEN-01 |
| POST | `/api/social-insurance-plan` | 新增方案 | BEN-01 |
| PUT | `/api/social-insurance-plan/{id}` | 修改方案 | BEN-01 |
| POST | `/api/social-insurance-account/page` | 参保账户 | BEN-02 |
| POST | `/api/social-insurance-change/batch` | 批量增减员 | BEN-02 |

---

## 十一、审批与权限（`/api`）

| 方法 | 路径 | 用途 | 需求 |
|---|---|---|---|
| GET | `/api/approval-flow/list` | 审批流模板 | SYS-03 |
| POST | `/api/approval-flow` | 新增模板 | SYS-03 |
| PUT | `/api/approval-flow/{id}` | 修改模板 | SYS-03 |
| GET | `/api/approval-flow/{id}/nodes` | 节点配置 | SYS-03 |
| POST | `/api/approval-flow/{id}/nodes` | 保存节点 | SYS-03 |
| POST | `/api/approval-instance/page` | 我的待办/已办 | SYS-03 |
| POST | `/api/approval/{instanceId}/approve` | 通过 | SYS-03 |
| POST | `/api/approval/{instanceId}/reject` | 驳回 | SYS-03 |
| GET | `/api/data-scope-rule/list` | 数据权限规则 | SYS-01 |
| POST | `/api/data-scope-rule` | 新增规则 | SYS-01 |
| DELETE | `/api/data-scope-rule/{id}` | 删除规则 | SYS-01 |
| POST | `/api/biz-change-log/page` | 业务变更日志 | SYS-04 |

---

## 十二、7 个关键接口的详细定义

### 12.1 规则解析预览 `GET /api/attendance-rule/resolve`

**为什么重要**：HR 配完规则后必须能自己验证"这个人这天到底按哪条规则算"。没有这个接口，规则配错了只能等月底看结果。

**请求**：`?employeeId=1001&date=2026-10-19`

**响应**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "employeeId": 1001,
    "empNo": "AH23010057",
    "workDate": "2026-10-19",
    "hitRule": {
      "ruleId": 12,
      "ruleName": "安徽瑞堂生产部规则",
      "scopeType": "DEPARTMENT",
      "scopeId": 88,
      "ruleVersion": 3,
      "effectiveFrom": "2026-07-01"
    },
    "resolvePath": [
      { "scopeType": "EMPLOYEE", "scopeId": 1001, "hit": false, "reason": "无个人规则" },
      { "scopeType": "TEAM", "scopeId": 205, "hit": false, "reason": "无班组规则" },
      { "scopeType": "DEPARTMENT", "scopeId": 88, "hit": true, "reason": "命中" },
      { "scopeType": "COMPANY", "scopeId": 2, "hit": false, "reason": "已在下级命中，不再向上查找" }
    ],
    "dayType": "WORKDAY",
    "isArranged": true,
    "isRequired": true,
    "shift": { "shiftId": 3, "shiftName": "白班 08:00-20:00", "source": "SCHEDULE" }
  }
}
```

**`resolvePath` 是关键**：不只告诉结果，还告诉**为什么是这个结果**。HR 拿这个就能自己排查。

---

### 12.2 打卡文件导入 `POST /api/attendance-punch/import`

**请求**：`multipart/form-data`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| file | File | 是 | Excel/CSV 文件 |
| terminalSn | String | 否 | 设备 SN；文件里没这列时用它兜底 |
| dryRun | Boolean | 否 | 是否只校验不落库，默认 false |

**响应**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "batchNo": "IMP20261019210001",
    "fileName": "得力考勤_202610.xlsx",
    "totalRows": 520,
    "successRows": 501,
    "failRows": 3,
    "unclaimedRows": 16,
    "status": "PARTIAL",
    "errorFileUrl": "/files/import/IMP20261019210001_errors.xlsx",
    "failSamples": [
      { "row": 12, "reason": "打卡时间格式无法识别：2026/13/45 08:00" },
      { "row": 88, "reason": "设备用户号 0099 未建立映射" }
    ]
  }
}
```

**三条设计约束**：

1. **同一文件 SHA-256 重复导入直接拒绝**（`14004`）。HR 手滑导两次，不能产生双份数据
2. **未匹配到工号的行不拒收**，进"待认领队列"。先让数据进得来，再让人认领——拒收会逼着 HR 手工改 Excel，效率更低
3. **`dryRun=true` 时只校验不落库**，让 HR 先看有多少错误行，再决定是否正式导入

---

### 12.3 单日考勤明细 `GET /api/attendance-day-result/detail`

**为什么重要**：这是"被质疑时能自证"的接口。

**请求**：`?employeeId=1001&date=2026-10-19`

**响应**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "employeeId": 1001,
    "empName": "张三",
    "workDate": "2026-10-19",
    "result": {
      "dayType": "WORKDAY",
      "isArranged": true,
      "isRequired": true,
      "shiftName": "白班 08:00-20:00",
      "requiredMinutes": 660,
      "workedMinutes": 615,
      "lateMinutes": 35,
      "earlyMinutes": 0,
      "absentMinutes": 0,
      "missingPunchCount": 0,
      "overtimeWorkdayMinutes": 0,
      "overtimeRestdayMinutes": 0,
      "overtimeHolidayMinutes": 0,
      "leaveMinutes": 0,
      "status": "ABNORMAL",
      "ruleVersion": 3,
      "calendarVersion": 2,
      "calcBatchNo": "CALC20261019001"
    },
    "punches": [
      { "punchTime": "2026-10-19 08:35:00", "terminalSn": "DL-D7_001", "punchType": "FACE", "source": "DEVICE_IMPORT", "used": true, "usedAs": "IN" },
      { "punchTime": "2026-10-19 20:00:00", "terminalSn": "DL-D7_001", "punchType": "FACE", "source": "DEVICE_IMPORT", "used": true, "usedAs": "OUT" }
    ],
    "docs": [],
    "explain": [
      "当日为工作日，且已排班（白班 08:00-20:00），判定为应出勤",
      "上班卡 08:35，班次上班时间 08:00，容差 5 分钟 → 迟到 30 分钟（08:05 之后计）",
      "下班卡 20:00，正常",
      "无请假、无出差、无申诉单据",
      "在岗 11h25m - 班内休息 1h = 10h15m，接近应出勤 11h，缺勤 45 分钟未达旷工阈值 240 分钟"
    ]
  }
}
```

**`explain` 数组是核心**。它把计算过程用人话讲出来，HR 和员工都能看懂，不用去翻代码。这个字段值不值得做，看法是：考勤争议 90% 是"为什么这么算"引起的，不是"算错了"引起的。

---

### 12.4 考勤重算 `POST /api/attendance-day-result/recalc`

**请求**：

```json
{
  "scopeType": "ORG_TREE",
  "scopeId": 88,
  "startDate": "2026-10-01",
  "endDate": "2026-10-31",
  "reason": "10月排班调整后重算",
  "force": false
}
```

**响应**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "calcBatchNo": "CALC20261019210500",
    "employeeCount": 128,
    "dayCount": 3968,
    "lockedSkipped": 0,
    "elapsedMs": 4210
  }
}
```

**约束**：

- `force=false` 时，**已锁定的日期跳过并在 `lockedSkipped` 里计数**，不报错
- `force=true` 需要额外权限，且会写 `biz_change_log`
- 重算幂等：同样输入重复跑，结果完全一致

---

### 12.5 轮班自动生成 `POST /api/shift-schedule/rotation`

**请求**：

```json
{
  "orgId": 88,
  "employeeIds": [1001, 1002, 1003],
  "startDate": "2026-11-01",
  "endDate": "2026-11-30",
  "rotationType": "THREE_SHIFT_TWO_TEAMS",
  "teamGrouping": [
    { "teamNo": 1, "employeeIds": [1001, 1002] },
    { "teamNo": 2, "employeeIds": [1003] }
  ],
  "overwrite": false
}
```

**响应**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "created": 120,
    "skipped": 4,
    "conflicts": [
      { "employeeId": 1003, "workDate": "2026-11-05", "reason": "已有排班，overwrite=false 时跳过" }
    ]
  }
}
```

**支持的班制**（`rotationType`）：`TWO_SHIFT` 两班倒、`THREE_SHIFT_TWO_TEAMS` 三班两倒、`FOUR_SHIFT_THREE_TEAMS` 四班三倒、`DAY_SHIFT` 常白班。

---

### 12.6 薪资试算 `POST /api/salary-calc/preview`

**请求**：

```json
{
  "closeMonth": "2026-10",
  "legalEntityId": 2,
  "employeeIds": null,
  "includeAttendance": true
}
```

**响应**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "batchNo": "PRE20261019211000",
    "employeeCount": 25,
    "totalGross": "285600.00",
    "totalNet": "241300.00",
    "details": [
      {
        "employeeId": 1001,
        "empNo": "AH23010057",
        "empName": "张三",
        "grossAmount": "12500.00",
        "deductionAmount": "2100.00",
        "netAmount": "10400.00",
        "items": [
          { "itemName": "基本工资", "amount": "8000.00", "calcDesc": "L9 三档" },
          { "itemName": "加班费", "amount": "1200.00", "calcDesc": "工作日加班 16h × 1.5 × 50元/h" },
          { "itemName": "计件工资", "amount": "1800.00", "calcDesc": "产量 3600 件 × 0.5 元" },
          { "itemName": "缺勤扣款", "amount": "-300.00", "calcDesc": "旷工 1 天 + 迟到 35 分钟" },
          { "itemName": "个人社保", "amount": "-1050.00", "calcDesc": "宁波 2026 年度" },
          { "itemName": "个人所得税", "amount": "-150.00", "calcDesc": "累计预扣预缴" }
        ]
      }
    ],
    "warnings": [
      { "employeeId": 1002, "warning": "本月加班 42 小时，超过上限 36 小时" },
      { "employeeId": 1003, "warning": "无薪档数据，基本工资按 0 计算" }
    ]
  }
}
```

**`warnings` 是必要的**：试算不报错但要提示异常，让 HR 在封账前发现"某人基本工资算成 0"这种问题。

---

### 12.7 职级影响人数预览 `GET /api/position-grade/{id}/impact`

**响应**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "gradeId": 5,
    "gradeName": "部门经理级",
    "employeeCount": 24,
    "positionCount": 18,
    "salaryPlanCount": 3,
    "impactAreas": ["薪资带宽", "审批金额权限", "编制统计"],
    "affectedEmployees": [
      { "employeeId": 1001, "empName": "张三", "orgName": "生产制造部", "positionName": "生产部经理" }
    ],
    "canDelete": false,
    "deleteBlockReason": "该职级被 24 名员工引用，只能停用不能删除"
  }
}
```

**为什么要这个接口**：改职级会影响薪酬和权限。先告诉 HR"这一改影响 24 个人"，再让他点确认，比事后排查便宜得多。

---

## 十三、接口与需求编号覆盖

| 域 | 接口数（约） | 覆盖 P0 需求 |
|---|---|---|
| 认证 | 5 | HR-SYS-06 |
| 组织与职位 | 31 | ORG-01～05、07、11、12、17、18 |
| 员工 | 30 | EMP-01～13、16、18、19 |
| 入转调离与合同 | 20 | LCM-01～09、CON-01～04、06 |
| 考勤 | 42 | ATT-01～14、17～20、24、28、29 |
| 假期 | 10 | LEA-01～06 |
| 薪酬与社保 | 24 | PAY-01～06、13～15、BEN-01、02 |
| 审批与权限 | 12 | SYS-01～04 |
| **合计** | **约 174** | P0 80 条 |

> 接口数（174）大于需求数（80），因为一条需求通常对应多个 CRUD 接口。

---

## 十四、待评审

| # | 事项 | 我的建议 |
|---|---|---|
| 1 | 业务接口 `/api` + 底座 `/system` 双风格并存 | 接受。改造底座会导致 RuoYi 升级时反复返工 |
| 2 | 分页用 `POST /api/xxx/page` 还是 `GET /api/xxx/list?pageNum=` | 用 POST。员工查询条件有十几个（组织、职级、状态、入职日期、关键字…），塞 URL 会超长 |
| 3 | 业务失败返回 HTTP 200 还是 4xx | 200 + `code`。RuoYi 前端拦截器按 `code` 判断，改成 4xx 要重写拦截器 |
| 4 | 是否对外开放接口（给财务/OA 调用） | 一期不做，`HR-SYS-11` 已在 P2 |
| 5 | 工资条是否要做二次验证 | 要做（`SYS-08`），查看他人薪资或导出必须有 |

---

## 十五、下一步

1. **考勤引擎 20 个边界场景转测试用例** → `4.测试资料`
2. **ER 图**（按域拆分）
3. 技术方案确认后进入编码，按域分批交付：组织→员工→考勤→薪酬
