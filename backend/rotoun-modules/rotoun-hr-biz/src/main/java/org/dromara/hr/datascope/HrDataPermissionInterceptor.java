package org.dromara.hr.datascope;

import com.baomidou.mybatisplus.core.toolkit.PluginUtils;
import com.baomidou.mybatisplus.extension.plugins.inner.BaseMultiTableInnerInterceptor;
import com.baomidou.mybatisplus.extension.plugins.inner.InnerInterceptor;
import lombok.extern.slf4j.Slf4j;
import net.sf.jsqlparser.expression.Expression;
import net.sf.jsqlparser.expression.operators.conditional.AndExpression;
import net.sf.jsqlparser.expression.operators.relational.ParenthesedExpressionList;
import net.sf.jsqlparser.parser.CCJSqlParserUtil;
import net.sf.jsqlparser.schema.Table;
import net.sf.jsqlparser.statement.Statement;
import net.sf.jsqlparser.statement.delete.Delete;
import net.sf.jsqlparser.statement.select.FromItem;
import net.sf.jsqlparser.statement.select.Join;
import net.sf.jsqlparser.statement.select.ParenthesedSelect;
import net.sf.jsqlparser.statement.select.PlainSelect;
import net.sf.jsqlparser.statement.select.Select;
import net.sf.jsqlparser.statement.select.SetOperationList;
import net.sf.jsqlparser.statement.update.Update;
import org.apache.ibatis.executor.Executor;
import org.apache.ibatis.executor.statement.StatementHandler;
import org.apache.ibatis.mapping.BoundSql;
import org.apache.ibatis.mapping.MappedStatement;
import org.apache.ibatis.mapping.SqlCommandType;
import org.apache.ibatis.session.ResultHandler;
import org.apache.ibatis.session.RowBounds;

import java.lang.reflect.Method;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.HashSet;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * HR 业务数据权限拦截器：只处理标注了 {@link HrDataScope} 的 Mapper 方法。
 *
 * <p>为什么另起一个拦截器而不改底座的 {@code PlusDataPermissionInterceptor}：
 * 底座那套读 {@code sys_role.data_scope} + {@code sys_dept}，本系统弃用 {@code sys_dept} 改用
 * {@code organization}，两套口径不能混。底座只在方法带 {@code @DataPermission} 时生效
 * （{@code PlusDataPermissionHandler#invalid()} 判断），因此底座可以原地保留，
 * 底座的系统管理页面照常工作，两套互不影响。
 *
 * <p>为什么继承 {@link BaseMultiTableInnerInterceptor}：多表 join 的 SQL 需要把条件挂到具体某张表上，
 * 这个解析逻辑 MP 已实现（{@link #buildTableExpression}），自己写容易在 join / union / 子查询上翻车。
 *
 * <p>为什么注解别名必填且找不到就抛异常：SQL 里一旦写错别名，条件会拼到不存在的表上，
 * 轻则全量放行（越权），重则 SQL 报错。这里选择运行时 fail-fast——宁可这次查询报错，
 * 也不让"少过滤"悄悄生效。
 */
@Slf4j
public class HrDataPermissionInterceptor extends BaseMultiTableInnerInterceptor implements InnerInterceptor {

    private final Map<String, Optional<HrDataScope>> annotationCache = new ConcurrentHashMap<>();
    private final HrDataScopeSqlBuilder builder = new HrDataScopeSqlBuilder();

    /**
     * 本次 SQL 要追加的条件片段；用 ThreadLocal 传给 {@link #buildTableExpression}，
     * 因为 MP 的多表解析流程不允许我们额外传参。
     */
    private final ThreadLocal<String> pendingSegment = new ThreadLocal<>();

    @Override
    public void beforeQuery(Executor executor, MappedStatement ms, Object parameter, RowBounds rowBounds,
                            ResultHandler resultHandler, BoundSql boundSql) throws SQLException {
        HrDataScope ann = resolveAnnotation(ms.getId());
        if (ann == null) {
            return;
        }
        String segment = builder.build(ann, HrContextHolder.get());
        if (segment == null) {
            // ALL：不加任何条件
            return;
        }
        // 别名必须真实存在于 SQL 中，否则这次查询直接失败（不静默放行）
        Set<String> aliases = collectAliases(boundSql.getSql(), ms.getId());
        requireAlias(aliases, ann.orgAlias(), ms.getId());
        requireAlias(aliases, ann.empAlias(), ms.getId());

        pendingSegment.set(segment);
        try {
            PluginUtils.MPBoundSql mpBs = PluginUtils.mpBoundSql(boundSql);
            mpBs.sql(parserSingle(mpBs.sql(), ms.getId()));
        } finally {
            pendingSegment.remove();
        }
    }

    @Override
    public void beforePrepare(StatementHandler sh, Connection connection, Integer transactionTimeout) {
        PluginUtils.MPStatementHandler mpSh = PluginUtils.mpStatementHandler(sh);
        MappedStatement ms = mpSh.mappedStatement();
        SqlCommandType sct = ms.getSqlCommandType();
        if (sct != SqlCommandType.UPDATE && sct != SqlCommandType.DELETE) {
            return;
        }
        HrDataScope ann = resolveAnnotation(ms.getId());
        if (ann == null) {
            return;
        }
        String segment = builder.build(ann, HrContextHolder.get());
        if (segment == null) {
            return;
        }
        // 改删同样收数据权限：没有规则就是 1=0，一条都改不动，不会误伤别人的数据
        Set<String> aliases = collectAliases(mpSh.mPBoundSql().sql(), ms.getId());
        requireAlias(aliases, ann.orgAlias(), ms.getId());
        requireAlias(aliases, ann.empAlias(), ms.getId());

        pendingSegment.set(segment);
        try {
            PluginUtils.MPBoundSql mpBs = mpSh.mPBoundSql();
            mpBs.sql(parserMulti(mpBs.sql(), ms.getId()));
        } finally {
            pendingSegment.remove();
        }
    }

    /**
     * 只把条件挂到注解声明的组织列别名所在的表上，其它表（如字典表、组织树）不加条件。
     */
    @Override
    public Expression buildTableExpression(Table table, Expression where, String whereSegment) {
        String segment = pendingSegment.get();
        if (segment == null) {
            return null;
        }
        String alias = table.getAlias() != null ? table.getAlias().getName() : table.getName();
        HrDataScope ann = currentAnnotation(whereSegment);
        if (ann == null || !alias.equalsIgnoreCase(ann.orgAlias())) {
            return null;
        }
        try {
            // 数据权限单独加一层括号，防止与业务条件的 AND/OR 优先级打架
            return new ParenthesedExpressionList<>(CCJSqlParserUtil.parseExpression(segment));
        } catch (Exception e) {
            throw new HrDataScopeException("数据权限条件解析失败：" + segment, e);
        }
    }

    /**
     * SELECT：交给 MP 的多表基类处理，它会遍历 from/join 的每张表并回调 {@link #buildTableExpression}。
     *
     * <p>为什么必须覆写：{@code JsqlParserSupport.processSelect} 的默认实现直接抛
     * {@code UnsupportedOperationException}，基类的多表入口是 {@code processSelectBody}，
     * 不覆写就等于"数据权限完全没生效"——而且不报错，属于最危险的静默失效。
     */
    @Override
    protected void processSelect(Select select, int index, String sql, Object obj) {
        String whereSegment = (obj instanceof String segment) ? segment : sql;
        processSelectBody(select, whereSegment);
    }

    /**
     * UPDATE：MP 的多表基类不处理 update，这里按底座的做法自行拼到 where 上。
     */
    @Override
    protected void processUpdate(Update update, int index, String sql, Object obj) {
        String segment = pendingSegment.get();
        if (segment == null) {
            return;
        }
        try {
            Expression expression = new ParenthesedExpressionList<>(CCJSqlParserUtil.parseExpression(segment));
            update.setWhere(appendWhere(update.getWhere(), expression));
        } catch (Exception e) {
            throw new HrDataScopeException("数据权限条件解析失败（UPDATE）：" + segment, e);
        }
    }

    /**
     * DELETE：同 {@link #processUpdate}。
     */
    @Override
    protected void processDelete(Delete delete, int index, String sql, Object obj) {
        String segment = pendingSegment.get();
        if (segment == null) {
            return;
        }
        try {
            Expression expression = new ParenthesedExpressionList<>(CCJSqlParserUtil.parseExpression(segment));
            delete.setWhere(appendWhere(delete.getWhere(), expression));
        } catch (Exception e) {
            throw new HrDataScopeException("数据权限条件解析失败（DELETE）：" + segment, e);
        }
    }

    private Expression appendWhere(Expression where, Expression condition) {
        if (where == null) {
            return condition;
        }
        return new AndExpression(where, condition);
    }

    private HrDataScope currentAnnotation(String whereSegment) {
        return whereSegment == null ? null : resolveAnnotation(whereSegment);
    }

    /**
     * 从 mapper 方法（或 mapper 接口）上取 {@link HrDataScope}；结果缓存，避免每条 SQL 都反射。
     */
    private HrDataScope resolveAnnotation(String msId) {
        if (msId == null) {
            return null;
        }
        return annotationCache.computeIfAbsent(msId, id -> {
            int idx = id.lastIndexOf('.');
            if (idx <= 0) {
                return Optional.empty();
            }
            String className = id.substring(0, idx);
            String methodName = id.substring(idx + 1);
            Class<?> clazz;
            try {
                clazz = Class.forName(className, false, Thread.currentThread().getContextClassLoader());
            } catch (ClassNotFoundException e) {
                // 非 mapper 方法（如 MP 内置的 statement），直接跳过
                return Optional.empty();
            }
            HrDataScope typeAnnotation = clazz.getAnnotation(HrDataScope.class);
            for (Method method : clazz.getMethods()) {
                if (method.getName().equals(methodName)) {
                    HrDataScope ann = method.getAnnotation(HrDataScope.class);
                    if (ann != null) {
                        return Optional.of(ann);
                    }
                }
            }
            return Optional.ofNullable(typeAnnotation);
        }).orElse(null);
    }

    private Set<String> collectAliases(String sql, String msId) {
        Set<String> aliases = new HashSet<>();
        try {
            Statement statement = CCJSqlParserUtil.parse(sql);
            collectFromStatement(statement, aliases);
        } catch (Exception e) {
            throw new HrDataScopeException("数据权限 SQL 解析失败：" + msId, e);
        }
        return aliases;
    }

    private void collectFromStatement(Statement statement, Set<String> aliases) {
        if (statement instanceof Select select) {
            collectFromSelect(select, aliases);
        } else if (statement instanceof Update update) {
            addTable(update.getTable(), aliases);
        } else if (statement instanceof Delete delete) {
            addTable(delete.getTable(), aliases);
        }
    }

    private void collectFromSelect(Select select, Set<String> aliases) {
        if (select instanceof PlainSelect plainSelect) {
            collectFromItem(plainSelect.getFromItem(), aliases);
            if (plainSelect.getJoins() != null) {
                for (Join join : plainSelect.getJoins()) {
                    collectFromItem(join.getRightItem(), aliases);
                }
            }
        } else if (select instanceof SetOperationList setOperationList) {
            for (Select item : setOperationList.getSelects()) {
                collectFromSelect(item, aliases);
            }
        }
    }

    private void collectFromItem(FromItem fromItem, Set<String> aliases) {
        if (fromItem == null) {
            return;
        }
        if (fromItem instanceof Table table) {
            addTable(table, aliases);
        } else if (fromItem instanceof ParenthesedSelect parenthesedSelect) {
            // 子查询：递归一层，覆盖 from (select ...) t 的常见写法
            // 这里不写 `instanceof Select inner`：编译目标是 Java 17，无条件 instanceof 模式要 21
            Select inner = parenthesedSelect.getSelect();
            if (inner != null) {
                collectFromSelect(inner, aliases);
            }
            if (parenthesedSelect.getAlias() != null) {
                aliases.add(parenthesedSelect.getAlias().getName());
            }
        }
    }

    private void addTable(Table table, Set<String> aliases) {
        if (table == null) {
            return;
        }
        if (table.getAlias() != null) {
            aliases.add(table.getAlias().getName());
        } else {
            aliases.add(table.getName());
        }
    }

    private void requireAlias(Set<String> aliases, String alias, String msId) {
        if (alias == null || alias.isBlank()) {
            return;
        }
        for (String item : aliases) {
            if (item.equalsIgnoreCase(alias)) {
                return;
            }
        }
        throw new HrDataScopeException("数据权限别名校验失败：SQL 中找不到别名 [" + alias + "]，"
            + "请检查 @HrDataScope 声明与 Mapper SQL 是否一致：" + msId);
    }
}
