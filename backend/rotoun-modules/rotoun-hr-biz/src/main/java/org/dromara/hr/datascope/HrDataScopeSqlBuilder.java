package org.dromara.hr.datascope;

import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.List;

/**
 * 数据权限规则 → SQL 条件片段。
 *
 * <p>四条硬规则（M0 清单 3.4）：
 * <ol>
 *     <li><b>默认拒绝</b>：没有上下文或没有规则 → {@code 1 = 0}。漏配权限时宁可看不到，不能全放。</li>
 *     <li><b>ALL 优先</b>：任一规则为 ALL → 不加任何条件。否则 OR 上 {@code 1 = 0} 会把全量又收窄。</li>
 *     <li><b>多角色并集</b>：规则之间 OR。兼任两个角色的人应当能看到两边的数据。</li>
 *     <li><b>值非法即报错</b>：{@code scope_value} 必须是正整数。它是拼进 SQL 的裸值，
 *         这里不放过任何非数字输入——规则表里被人塞进 {@code "1) OR 1=1 --"} 就是一次注入。</li>
 * </ol>
 *
 * <p>本类不依赖 Spring，可在毫秒级单测里直接跑（对应 M0 清单 3.9 的 12 条验收用例）。
 */
@Slf4j
public class HrDataScopeSqlBuilder {

    /** 默认拒绝条件 */
    public static final String DENY = "1 = 0";

    /**
     * 生成数据范围条件。
     *
     * @param ann 注解（提供别名与列名）
     * @param ctx 登录上下文（提供规则、员工 ID）
     * @return SQL 条件片段；返回 {@code null} 表示"不追加任何条件"（ALL 或未标注注解）
     */
    public String build(HrDataScope ann, HrLoginContext ctx) {
        if (ann == null) {
            return null;
        }
        if (ctx == null || ctx.getScopeRules() == null || ctx.getScopeRules().isEmpty()) {
            // 无上下文：要么是未登录（理论上已被鉴权拦掉），要么是装配失败。
            // 两条路都不能放行，统一按"看不到"处理。
            return DENY;
        }

        List<HrDataScopeRule> rules = ctx.getScopeRules();
        for (HrDataScopeRule rule : rules) {
            if (rule != null && rule.isAll()) {
                return null;
            }
        }

        List<Long> companyIds = new ArrayList<>();
        List<Long> orgIds = new ArrayList<>();
        List<String> pathPrefixes = new ArrayList<>();
        boolean self = false;

        for (HrDataScopeRule rule : rules) {
            if (rule == null) {
                continue;
            }
            HrDataScopeType type = HrDataScopeType.of(rule.getScopeType());
            if (type == null) {
                // 未知类型：不猜、不放行，跳过并在日志里留证据
                log.warn("[数据权限] 忽略无法识别的 scope_type：roleId={}, scopeType={}",
                    rule.getRoleId(), rule.getScopeType());
                continue;
            }
            switch (type) {
                case COMPANY -> companyIds.add(requirePositiveId(rule, "COMPANY"));
                case ORG -> orgIds.add(requirePositiveId(rule, "ORG"));
                case ORG_TREE -> {
                    String prefix = rule.getPathPrefix();
                    if (prefix == null || prefix.isBlank()) {
                        // 装配层没解析出路径前缀：跳过该规则，最终若一条都没有则落到 DENY
                        log.warn("[数据权限] ORG_TREE 规则缺少路径前缀，已跳过：roleId={}, scopeValue={}",
                            rule.getRoleId(), rule.getScopeValue());
                        continue;
                    }
                    pathPrefixes.add(prefix);
                }
                case SELF -> self = true;
                default -> {
                    // ALL 已在上面提前返回
                }
            }
        }

        List<String> conditions = new ArrayList<>();
        if (!companyIds.isEmpty()) {
            conditions.add(in(legalAlias(ann), ann.legalColumn(), companyIds));
        }
        if (!orgIds.isEmpty()) {
            conditions.add(in(ann.orgAlias(), ann.orgColumn(), orgIds));
        }
        for (String prefix : pathPrefixes) {
            conditions.add(ann.orgAlias() + "." + ann.orgPathColumn() + " LIKE '" + escapeLike(prefix) + "%'");
        }
        if (self) {
            Long employeeId = ctx.getEmployeeId();
            if (employeeId == null) {
                // 纯管理员没有员工档案：SELF 无意义，不能退化成全量，按"看不到"处理
                log.warn("[数据权限] SELF 规则但登录上下文无 employeeId（纯管理员）：userId={}", ctx.getUserId());
            } else {
                conditions.add(ann.empAlias() + "." + ann.empColumn() + " = " + employeeId);
            }
        }

        if (conditions.isEmpty()) {
            return DENY;
        }
        return String.join(" OR ", conditions);
    }

    private String in(String alias, String column, List<Long> ids) {
        StringBuilder sb = new StringBuilder(alias).append('.').append(column).append(" IN (");
        for (int i = 0; i < ids.size(); i++) {
            if (i > 0) {
                sb.append(", ");
            }
            sb.append(ids.get(i));
        }
        return sb.append(')').toString();
    }

    private String legalAlias(HrDataScope ann) {
        String legal = ann.legalAlias();
        return (legal == null || legal.isBlank()) ? ann.orgAlias() : legal;
    }

    /**
     * 规则取值必须为正整数：这是拼进 SQL 的裸值，必须从源头掐断注入可能。
     */
    private long requirePositiveId(HrDataScopeRule rule, String typeName) {
        String raw = rule.getScopeValue();
        long id;
        try {
            id = Long.parseLong(raw.trim());
        } catch (Exception e) {
            throw new HrDataScopeException("数据权限规则取值非法，" + typeName + " 需要正整数 ID：roleId="
                + rule.getRoleId() + ", scopeValue=" + raw);
        }
        if (id <= 0) {
            throw new HrDataScopeException("数据权限规则取值非法，" + typeName + " 需要正整数 ID：roleId="
                + rule.getRoleId() + ", scopeValue=" + raw);
        }
        return id;
    }

    /**
     * LIKE 片段的单引号转义。组织路径理论上只有数字和斜杠，但转义是零成本的事前防护。
     */
    private String escapeLike(String value) {
        return value.replace("'", "''").replace("\\", "\\\\");
    }
}
