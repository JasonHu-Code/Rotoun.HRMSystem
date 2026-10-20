package org.dromara.hr.datascope;

/**
 * 数据权限异常：SQL 解析失败、别名缺失、规则值非法等。
 *
 * <p>为什么单独定义而不是复用底座 {@code ServiceException}：这类异常意味着"系统配错了"，
 * 需要被全局异常处理器单独归类（错误码 10xxx 业务异常段）并打 ERROR 日志，
 * 与普通业务校验失败区分开，方便上线后快速定位是权限配置问题还是业务问题。
 */
public class HrDataScopeException extends RuntimeException {

    /** 错误码：10403 数据权限异常 */
    public static final int CODE = 10403;

    private final int code;

    public HrDataScopeException(String message) {
        this(CODE, message);
    }

    public HrDataScopeException(int code, String message) {
        super(message);
        this.code = code;
    }

    public HrDataScopeException(String message, Throwable cause) {
        this(CODE, message, cause);
    }

    public HrDataScopeException(int code, String message, Throwable cause) {
        super(message, cause);
        this.code = code;
    }

    public int getCode() {
        return code;
    }
}
