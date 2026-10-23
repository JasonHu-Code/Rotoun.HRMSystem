package org.dromara.hr.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.dromara.hr.datascope.HrDataScope;
import org.dromara.hr.domain.Employee;
import org.dromara.hr.domain.vo.EmployeeScopeRow;

import java.util.List;

/**
 * 员工主数据 Mapper。
 *
 * <p>{@link #selectScopeRows()} 是本模块第一条带 {@link HrDataScope} 的业务查询，
 * 也是 M0 验收用例的载体：它同时用到组织列（{@code em.organization_id}）、法人列
 * （{@code em.legal_entity_id}）和员工列（{@code e.id}），五种范围类型都能在这条 SQL 上验证。
 */
public interface EmployeeMapper extends BaseMapper<Employee> {

    /**
     * 按登录账号查员工 ID（account → employee 的绑定链起点）。
     *
     * <p>手写 SQL 要显式带 {@code is_deleted = 0}：{@code @Select} 绕过 MP 的逻辑删除拼接，
     * 漏写会把已删除员工也查出来。
     */
    @Select("SELECT id FROM employee WHERE sys_user_id = #{userId} AND is_deleted = 0 LIMIT 1")
    Long selectIdBySysUserId(@Param("userId") Long userId);

    /**
     * 员工列表（主岗维度）。数据权限由 {@link HrDataScope} 在 SQL 层追加条件，不是查完再过滤。
     */
    @Select("""
        SELECT e.id          AS id,
               e.emp_no      AS empNo,
               e.emp_name    AS empName,
               em.organization_id AS organizationId,
               em.legal_entity_id AS legalEntityId
        FROM employee e
        JOIN employment em ON em.employee_id = e.id
             AND em.is_current = 1
             AND em.employment_type = 'PRIMARY'
             AND em.is_deleted = 0
        WHERE e.is_deleted = 0
        ORDER BY e.id
        """)
    @HrDataScope(orgAlias = "em", empAlias = "e", empColumn = "id")
    List<EmployeeScopeRow> selectScopeRows();
}
