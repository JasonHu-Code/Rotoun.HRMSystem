package org.dromara.hr.datascope;

import com.baomidou.mybatisplus.extension.plugins.MybatisPlusInterceptor;
import com.baomidou.mybatisplus.extension.plugins.inner.InnerInterceptor;
import com.baomidou.mybatisplus.extension.plugins.inner.PaginationInnerInterceptor;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 挂载器测试。
 *
 * <p>为什么单独测：单测里用 mock/自建列表验证过"插在分页之前"，但真实
 * {@code MybatisPlusInterceptor#getInterceptors()} 返回的是不可修改视图，
 * 直接 add 会抛 UnsupportedOperationException，这条路径只有接到真实容器上才暴露。
 * 因此这里必须用真实的 MybatisPlusInterceptor 跑一遍。
 */
class HrDataPermissionRegistrarTest {

    @Test
    void 接到真实MP拦截器上时能挂上且不破坏分页插件() {
        MybatisPlusInterceptor mp = new MybatisPlusInterceptor();
        PaginationInnerInterceptor pagination = new PaginationInnerInterceptor();
        mp.addInnerInterceptor(pagination);

        HrDataPermissionInterceptor hr = new HrDataPermissionInterceptor();
        new HrDataPermissionRegistrar(mp, hr).afterPropertiesSet();

        List<InnerInterceptor> chain = mp.getInterceptors();
        assertEquals(2, chain.size(), "分页插件必须还在，不能被顶掉");
        assertSame(hr, chain.get(0), "数据权限必须排在分页之前，否则 count 统计不到过滤结果");
        assertSame(pagination, chain.get(1));
    }

    @Test
    void 重复调用不会重复挂载() {
        MybatisPlusInterceptor mp = new MybatisPlusInterceptor();
        mp.addInnerInterceptor(new PaginationInnerInterceptor());
        HrDataPermissionInterceptor hr = new HrDataPermissionInterceptor();
        HrDataPermissionRegistrar registrar = new HrDataPermissionRegistrar(mp, hr);

        registrar.afterPropertiesSet();
        registrar.afterPropertiesSet();

        assertEquals(2, mp.getInterceptors().size());
    }

    @Test
    void 没有分页插件时追加到末尾() {
        MybatisPlusInterceptor mp = new MybatisPlusInterceptor();
        HrDataPermissionInterceptor hr = new HrDataPermissionInterceptor();

        new HrDataPermissionRegistrar(mp, hr).afterPropertiesSet();

        List<InnerInterceptor> chain = mp.getInterceptors();
        assertEquals(1, chain.size());
        assertTrue(chain.contains(hr));
    }
}
