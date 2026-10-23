package org.dromara.hr.datascope;

import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.dromara.common.core.domain.R;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * 数据权限异常 → 403。
 *
 * <p>不加这段的话，{@link HrDataScopeException} 会被底座的兜底处理器当成未知异常返回 500，
 * 前端只看到"系统错误"，运维也分不清是权限配置错还是服务挂了。这里显式映射成 403 + 10403，
 * 并把 ERROR 日志留在服务端（前端不需要知道是哪个别名写错了）。
 *
 * <p>注意：<b>不要</b>把 {@code message} 里的 SQL 片段带出去——那等于把表结构告诉调用方。
 * 当前 message 只描述"哪条规则配错了"，不含 SQL。
 */
@Slf4j
@RestControllerAdvice
public class HrDataScopeExceptionHandler {

    @ExceptionHandler(HrDataScopeException.class)
    public R<Void> handle(HrDataScopeException e, HttpServletResponse response) {
        log.error("[HR数据权限] {}", e.getMessage(), e);
        response.setStatus(HttpStatus.FORBIDDEN.value());
        return R.fail(e.getCode(), e.getMessage());
    }
}
