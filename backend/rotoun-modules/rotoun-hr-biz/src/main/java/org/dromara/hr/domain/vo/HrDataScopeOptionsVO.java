package org.dromara.hr.domain.vo;

import lombok.Data;

import java.io.Serial;
import java.io.Serializable;
import java.util.List;

/**
 * 数据权限配置页的选项包：一次请求把下拉数据取全，避免页面打开时连发三个请求。
 */
@Data
public class HrDataScopeOptionsVO implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    /** 法人（COMPANY 范围用） */
    private List<IdNameOption> legalEntities;

    /** 组织（ORG / ORG_TREE 范围用） */
    private List<IdNameOption> organizations;

    /** 组织为空时的提示语，前端直接展示，省得两边各写一份判断 */
    private boolean organizationEmpty;
}
