package org.dromara.hr.config;

import lombok.RequiredArgsConstructor;
import org.dromara.hr.auth.HrLoginContextInterceptor;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * 注册 HR 登录上下文拦截器。
 *
 * <p>排除项只放"没有身份也应当正常返回"的路径（错误页、健康检查、接口文档）。
 * 其余路径一律挂上——挂上不等于强制登录，拦截器内部会判断 {@code StpUtil.isLogin()}，
 * 未登录直接跳过，由底座鉴权负责拦。
 */
@Configuration
@RequiredArgsConstructor
public class HrWebMvcConfig implements WebMvcConfigurer {

    private final HrLoginContextInterceptor hrLoginContextInterceptor;

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(hrLoginContextInterceptor)
            .addPathPatterns("/**")
            .excludePathPatterns(
                "/error",
                "/favicon.ico",
                "/actuator/**",
                "/swagger-ui/**",
                "/swagger-ui.html",
                "/v3/api-docs/**"
            );
    }
}
