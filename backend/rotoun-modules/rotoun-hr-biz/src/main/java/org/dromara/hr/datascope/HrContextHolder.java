package org.dromara.hr.datascope;

/**
 * 登录上下文的线程持有者。
 *
 * <p>装配与清除由 {@code HrLoginContextInterceptor} 负责（M0-B 已落地），数据权限拦截器只读不写：
 * 拦截器读不到上下文时按"无规则"处理（拼 {@code 1 = 0}），不抛异常也不放行，
 * 这样即使过滤器漏配，最坏结果是"看不到数据"而不是"越权看全量"。
 */
public final class HrContextHolder {

    private static final ThreadLocal<HrLoginContext> HOLDER = new ThreadLocal<>();

    private HrContextHolder() {
    }

    public static HrLoginContext get() {
        return HOLDER.get();
    }

    public static void set(HrLoginContext context) {
        HOLDER.set(context);
    }

    public static void clear() {
        HOLDER.remove();
    }
}
