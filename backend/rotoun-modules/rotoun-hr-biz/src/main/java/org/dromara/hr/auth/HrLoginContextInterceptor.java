package org.dromara.hr.auth;

import cn.dev33.satoken.stp.StpUtil;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.dromara.hr.datascope.HrContextHolder;
import org.dromara.hr.datascope.HrLoginContext;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * 请求级装配：把 {@link HrLoginContext} 放进 ThreadLocal，请求结束必须清掉。
 *
 * <p>为什么是拦截器而不是 Filter：Sa-Token 的上下文（{@code SaHolder}）由它自己的 ServletFilter 准备，
 * 如果我们的 Filter 排在它前面，{@code StpUtil.isLogin()} 拿不到 token，上下文永远装配不出来。
 * 拦截器天然在所有 Filter 之后执行，顺序问题不存在。
 *
 * <p>为什么 {@code afterCompletion} 一定要 clear：Tomcat 线程是复用的，不清就会把上一个请求的
 * 身份留给下一个请求——那是标准的越权事故。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class HrLoginContextInterceptor implements HandlerInterceptor {

    private final HrLoginContextLoader loader;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        HrContextHolder.clear();
        if (!StpUtil.isLogin()) {
            return true;
        }
        try {
            Long userId = StpUtil.getLoginIdAsLong();
            HrLoginContext ctx = loader.getOrLoad(userId);
            HrContextHolder.set(ctx);
        } catch (Exception e) {
            // 装配失败不放行、也不 500：拦截器读不到上下文时按"无规则"处理，结果是查不到数据。
            // 这里必须打 error 日志，否则线上会表现为"用户突然什么都看不到"而无从排查。
            log.error("[HR上下文] 装配失败，本次请求按无数据权限处理：uri={}", request.getRequestURI(), e);
        }
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response,
                                Object handler, Exception ex) {
        HrContextHolder.clear();
    }
}
