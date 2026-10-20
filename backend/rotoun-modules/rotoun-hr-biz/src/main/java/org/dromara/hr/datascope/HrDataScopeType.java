package org.dromara.hr.datascope;

import lombok.Getter;

import java.util.Arrays;

/**
 * 数据范围类型，取值以 {@code data_scope_rule.scope_type} 的 DDL 为准：
 * {@code ALL / COMPANY / ORG_TREE / ORG / SELF}。
 *
 * <p>为什么不用数据库设计文档里的 {@code CUSTOM}：文档与 DDL 曾出现两个口径（文档 CUSTOM / DDL SELF），
 * 已裁定以 DDL 为准。这里只认 DDL 的五个值，出现其它值一律按"未知类型"处理并拒绝放行，
 * 不让脏数据悄悄退化成全量可见。
 */
@Getter
public enum HrDataScopeType {

    /** 全量可见 */
    ALL("ALL", "全量"),
    /** 本公司（法人） */
    COMPANY("COMPANY", "本公司"),
    /** 指定组织及其子树 */
    ORG_TREE("ORG_TREE", "组织及子树"),
    /** 仅指定组织（不含子组织） */
    ORG("ORG", "本组织"),
    /** 仅本人 */
    SELF("SELF", "仅本人"),
    ;

    private final String code;
    private final String desc;

    HrDataScopeType(String code, String desc) {
        this.code = code;
        this.desc = desc;
    }

    /**
     * 按 code 解析；无法识别返回 null，由调用方决定忽略还是报错（不允许默认当成 ALL）。
     */
    public static HrDataScopeType of(String code) {
        if (code == null || code.isBlank()) {
            return null;
        }
        String trimmed = code.trim();
        return Arrays.stream(values())
            .filter(t -> t.code.equalsIgnoreCase(trimmed))
            .findFirst()
            .orElse(null);
    }
}
