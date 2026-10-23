package org.dromara.hr.mapper;

import org.apache.ibatis.annotations.Select;
import org.dromara.hr.domain.vo.IdNameOption;

import java.util.List;

/**
 * 配置页需要的下拉数据（法人、组织）。
 *
 * <p>只读、只取两列，不复用组织模块将来的复杂查询——配置数据权限时只需要"选一个 id"，
 * 带上组织负责人、成本中心那些字段没有意义。
 */
public interface HrOptionMapper {

    /**
     * 法人列表：COMPANY 范围选这里。
     */
    @Select("""
        SELECT id AS id, entity_name AS name
        FROM legal_entity
        WHERE is_deleted = 0
        ORDER BY is_group DESC, sort_no, id
        """)
    List<IdNameOption> selectLegalEntities();

    /**
     * 组织列表：ORG / ORG_TREE 范围选这里。
     * 名称里带层级缩进没意义（下拉不好看），这里给出全称 + 编码，配合 filterable 搜索足够用。
     */
    @Select("""
        SELECT id AS id, CONCAT(org_name, ' · ', org_code) AS name
        FROM organization
        WHERE is_deleted = 0 AND status = 'ENABLED'
        ORDER BY org_path
        """)
    List<IdNameOption> selectOrganizations();
}
