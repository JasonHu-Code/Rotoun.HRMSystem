package org.dromara.hr.datascope;

import com.baomidou.mybatisplus.extension.plugins.MybatisPlusInterceptor;
import com.baomidou.mybatisplus.extension.plugins.inner.InnerInterceptor;
import com.baomidou.mybatisplus.extension.plugins.inner.PaginationInnerInterceptor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.InitializingBean;

import java.util.List;

/**
 * 把 HR 数据权限拦截器挂到 MP 拦截器链上。
 *
 * <p>为什么不能在自己的 {@code @Configuration} 里 new 一个 {@code MybatisPlusInterceptor}：
 * 底座已经在 {@code MybatisPlusConfig} 里注册了这个 bean，再注册一个会互相覆盖，分页插件会丢。
 * 因此这里只做"往已有链里插一个"，不动底座的任何东西。
 *
 * <p>为什么必须插在 {@link PaginationInnerInterceptor} <b>之前</b>：分页插件会先把 SQL 包成
 * {@code select count(*) from (原SQL) total}，若数据权限后执行，看到的就是这层包装，
 * 原 SQL 的别名在子查询里，别名校验必然失败，count 也统计不到过滤后的结果。
 */
@Slf4j
public class HrDataPermissionRegistrar implements InitializingBean {

    private final MybatisPlusInterceptor mybatisPlusInterceptor;
    private final HrDataPermissionInterceptor hrDataPermissionInterceptor;

    public HrDataPermissionRegistrar(MybatisPlusInterceptor mybatisPlusInterceptor,
                                     HrDataPermissionInterceptor hrDataPermissionInterceptor) {
        this.mybatisPlusInterceptor = mybatisPlusInterceptor;
        this.hrDataPermissionInterceptor = hrDataPermissionInterceptor;
    }

    @Override
    public void afterPropertiesSet() {
        List<InnerInterceptor> interceptors = mybatisPlusInterceptor.getInterceptors();
        if (interceptors.contains(hrDataPermissionInterceptor)) {
            return;
        }
        int paginationIndex = -1;
        for (int i = 0; i < interceptors.size(); i++) {
            if (interceptors.get(i) instanceof PaginationInnerInterceptor) {
                paginationIndex = i;
                break;
            }
        }
        if (paginationIndex >= 0) {
            interceptors.add(paginationIndex, hrDataPermissionInterceptor);
        } else {
            interceptors.add(hrDataPermissionInterceptor);
        }
        log.info("[HR数据权限] 已挂载 HrDataPermissionInterceptor，位置 {}，当前拦截器链 {}",
            paginationIndex >= 0 ? paginationIndex : interceptors.size() - 1, interceptors);
    }
}
