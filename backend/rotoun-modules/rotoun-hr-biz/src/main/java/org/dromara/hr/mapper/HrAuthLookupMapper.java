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
 * 会把模块边界打穿（系统模块以后想引用业务就成环了）。这里只写几句只读 SQL，
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

    /**
     * 角色下的账号 ID：改规则后要逐个清登录上下文缓存，否则最长 8 小时不生效。
     */
    @Select("SELECT user_id FROM sys_user_role WHERE role_id = #{roleId}")
    List<Long> selectUserIdsByRoleId(@Param("roleId") Long roleId);

    /**
     * 角色是否存在（允许配置数据权限的角色必须是有效角色）。
     */
    @Select("SELECT COUNT(*) FROM sys_role WHERE role_id = #{roleId} AND del_flag = '0'")
    int countRole(@Param("roleId") Long roleId);

    /**
     * 法人名称：规则列表里要把 COMPANY 的 scope_value 翻译成人看得懂的名字。
     */
    @Select("SELECT entity_name FROM legal_entity WHERE id = #{id} AND is_deleted = 0")
    String selectLegalEntityName(@Param("id") Long id);

    /**
     * 法人是否存在：配规则时就要挡住"指向不存在的法人"，不要等到运行期才 1=0。
     */
    @Select("SELECT COUNT(*) FROM legal_entity WHERE id = #{id} AND is_deleted = 0")
    int countLegalEntity(@Param("id") Long id);
}
