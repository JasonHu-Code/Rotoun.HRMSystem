package org.dromara.hr.datascope;

/**
 * 导出闸门：数据范围与"能不能导出"是两件事。
 *
 * <p>M0 验收用例 8 的口径是"列表可见、导出 403"：一个只能看本公司的人，不代表允许把这批人导成 Excel
 * 带走。因此可见性由 {@code data_scope_rule} 决定，导出另由 {@code can_export} 决定，
 * 两处判断分开写，避免有人在列表接口里顺手复用了导出权限。
 *
 * <p>默认拒绝：上下文中没有任何一条规则声明可导出，就不可导出。
 */
public final class HrExportGuard {

    private HrExportGuard() {
    }

    /**
     * 校验导出权限，不允许时抛 {@link HrDataScopeException}（HTTP 403）。
     */
    public static void check(HrLoginContext ctx) {
        if (ctx == null || !ctx.isCanExport()) {
            throw new HrDataScopeException("当前账号无导出权限");
        }
    }

    public static boolean canExport(HrLoginContext ctx) {
        return ctx != null && ctx.isCanExport();
    }
}
