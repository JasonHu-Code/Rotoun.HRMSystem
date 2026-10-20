package org.dromara.hr.datascope;

import com.baomidou.mybatisplus.extension.plugins.MybatisPlusInterceptor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * HR 数据权限装配。
 *
 * <p>注意：这里<b>不</b>注册 {@code MybatisPlusInterceptor}（底座已注册），
 * 只注册我们的拦截器 + 一个把它插进拦截器链的 {@link HrDataPermissionRegistrar}。
 * 这样底座的数据权限 {@code PlusDataPermissionInterceptor} 保持原样，两边互不干扰。
 */
@Configuration
public class HrDataPermissionConfig {

    @Bean
    public HrDataPermissionInterceptor hrDataPermissionInterceptor() {
        return new HrDataPermissionInterceptor();
    }

    @Bean
    public HrDataPermissionRegistrar hrDataPermissionRegistrar(MybatisPlusInterceptor mybatisPlusInterceptor,
                                                              HrDataPermissionInterceptor hrDataPermissionInterceptor) {
        return new HrDataPermissionRegistrar(mybatisPlusInterceptor, hrDataPermissionInterceptor);
    }
}
