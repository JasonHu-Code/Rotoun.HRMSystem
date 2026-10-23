package org.dromara.hr.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.dromara.hr.domain.vo.RoleRef;

import java.util.List;

/**
 * 登录账号 → 角色 的只读查询。
 *
 * <p>为什么不依赖 {@code rotoun-system} 模块的 {@code SysRoleMapper}：业务模块反向依赖系统模块
 * 会把模块边界打穿（系统模块以后想引用业务就成环了）。这里只写两句只读 SQL，
 * 表结构由底座维护，字段名是稳定契约。
 */
public interface HrAuthLookupMapper {

    /**
     * 查账号的有效角色。停用角色（status='1'）与已删除角色不参与数据权限。
     */
    @Select("""
        SELECT r.role_id  AS roleId,
               r.role_key AS roleKey
        FROM sys_user_role ur
        JOIN sys_role r ON r.role_id = ur.role_id
        WHERE ur.user_id = #{userId}
          AND r.status = '0'
          AND r.del_flag = '0'
        """)
    List<RoleRef> selectRolesByUserId(@Param("userId") Long userId);
}
