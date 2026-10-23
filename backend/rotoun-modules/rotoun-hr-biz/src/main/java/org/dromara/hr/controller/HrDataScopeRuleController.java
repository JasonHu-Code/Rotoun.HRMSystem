package org.dromara.hr.controller;

import cn.dev33.satoken.annotation.SaCheckPermission;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.dromara.common.core.domain.R;
import org.dromara.hr.domain.dto.HrDataScopeRuleSaveDTO;
import org.dromara.hr.domain.vo.HrDataScopeOptionsVO;
import org.dromara.hr.domain.vo.HrDataScopeRuleVO;
import org.dromara.hr.service.HrDataScopeRuleService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 角色数据权限配置。
 *
 * <p>路径走业务风格 {@code /api/xxx-yyy}（小写横线），与底座 {@code /system/**} 区分开——
 * 这既是规范要求，也方便网关/日志按前缀分流。
 *
 * <p>权限沿用底座的 {@code system:role:edit}：数据权限本质是角色配置的一部分，
 * 再单独造一个权限点会让"能改角色但不能改数据权限"变成默认状态，反而容易出现没人负责的情况。
 */
@RestController
@RequestMapping("/api/data-scope-rule")
@RequiredArgsConstructor
public class HrDataScopeRuleController {

    private final HrDataScopeRuleService ruleService;

    /**
     * 某角色的规则列表。
     */
    @SaCheckPermission("system:role:edit")
    @GetMapping("/list")
    public R<List<HrDataScopeRuleVO>> list(@RequestParam Long roleId) {
        return R.ok(ruleService.list(roleId));
    }

    /**
     * 配置页下拉数据：法人 + 组织。
     */
    @SaCheckPermission("system:role:edit")
    @GetMapping("/options")
    public R<HrDataScopeOptionsVO> options() {
        return R.ok(ruleService.options());
    }

    /**
     * 全量保存某角色的规则。保存成功后会清理该角色下所有账号的登录上下文缓存。
     */
    @SaCheckPermission("system:role:edit")
    @PostMapping("/save")
    public R<Void> save(@Valid @RequestBody HrDataScopeRuleSaveDTO dto) {
        ruleService.save(dto.getRoleId(), dto.getRules());
        return R.ok("保存成功");
    }
}
