package org.dromara.hr.domain.vo;

import lombok.Data;

import java.io.Serial;
import java.io.Serializable;

/**
 * 通用下拉选项（id + 展示名）。用于法人与组织的选择器。
 */
@Data
public class IdNameOption implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    private Long id;

    private String name;
}
