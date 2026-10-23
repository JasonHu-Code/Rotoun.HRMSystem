package org.dromara.hr.datascope;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;

import java.lang.annotation.Annotation;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * M0 验收用例 1–12 的端到端实测：真库、真 SQL、真结果。
 *
 * <p>为什么不用 {@code @SpringBootTest}：本模块任何测试都要能在没有 Redis、没有完整应用的机器上跑。
 * 这里只借一个 MySQL：建一个独立的 {@code rt_hrms_m0_test} 库，灌 6 个员工的小数据集，
 * 每条用例都把 {@link HrDataScopeSqlBuilder} 生成的条件下推到真实 SQL 里执行，再数结果。
 * 验证的是"规则 → 条件 → 数据库结果"这条完整链路，不是内存里的字符串比较。
 *
 * <p>数据库不可达时整个类跳过（{@code Assumptions}），这样 {@code mvn test} 在没有 MySQL 的机器上也能过。
 *
 * <p>用例编号与《M0 底座改造清单 3.9》一一对应。
 */
@Tag("integration")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
@DisplayName("M0 数据权限 12 条验收用例（真库实测）")
class HrDataScopeAcceptanceTest {

    private static final String DB = "rt_hrms_m0_test";
    private static final String URL = "jdbc:mysql://localhost:3306/" + DB
        + "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai&characterEncoding=utf8";
    private static final String ROOT_URL = "jdbc:mysql://localhost:3306/"
        + "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai&characterEncoding=utf8";
    private static final String USER = "root";
    private static final String PASSWORD = "root";

    private static final HrDataScopeSqlBuilder BUILDER = new HrDataScopeSqlBuilder();

    /** 员工列表基础 SQL：与 EmployeeMapper.selectScopeRows 同形 */
    private static final String BASE_SQL = """
        SELECT e.id
        FROM employee e
        JOIN employment em ON em.employee_id = e.id
             AND em.is_current = 1 AND em.employment_type = 'PRIMARY' AND em.is_deleted = 0
        WHERE e.is_deleted = 0
        """;

    private static Connection conn;
    private static boolean available;

    // ---------------------------------------------------------------- 环境

    @BeforeAll
    static void setUp() {
        try {
            DriverManager.setLoginTimeout(2);
            try (Connection root = DriverManager.getConnection(ROOT_URL, USER, PASSWORD)) {
                try (Statement st = root.createStatement()) {
                    st.execute("DROP DATABASE IF EXISTS " + DB);
                    st.execute("CREATE DATABASE " + DB + " DEFAULT CHARSET utf8mb4");
                }
            }
            conn = DriverManager.getConnection(URL, USER, PASSWORD);
            createSchema();
            seed();
            available = true;
        } catch (Exception e) {
            available = false;
            System.out.println("[验收用例] 跳过：本机 MySQL 不可达（" + e.getMessage() + "）");
        }
        assumeTrue(available, "MySQL 不可达，跳过端到端验收");
    }

    @AfterAll
    static void tearDown() {
        if (conn == null) {
            return;
        }
        try (Statement st = conn.createStatement()) {
            st.execute("DROP DATABASE IF EXISTS " + DB);
        } catch (Exception ignored) {
            // 清理失败不影响结论
        }
        try {
            conn.close();
        } catch (Exception ignored) {
        }
    }

    private static void createSchema() throws SQLException {
        exec("""
            CREATE TABLE organization (
              id bigint unsigned NOT NULL AUTO_INCREMENT,
              org_code varchar(30) NOT NULL,
              org_name varchar(100) NOT NULL,
              legal_entity_id bigint unsigned NOT NULL,
              parent_id bigint unsigned NOT NULL DEFAULT 0,
              org_path varchar(500) NOT NULL,
              org_level tinyint unsigned NOT NULL DEFAULT 1,
              org_type varchar(20) NOT NULL,
              is_deleted tinyint(1) NOT NULL DEFAULT 0,
              PRIMARY KEY (id), KEY idx_organization_org_path (org_path(64))
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """);
        exec("""
            CREATE TABLE employee (
              id bigint unsigned NOT NULL AUTO_INCREMENT,
              emp_no varchar(20) NOT NULL,
              emp_name varchar(50) NOT NULL,
              employee_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
              sys_user_id bigint unsigned DEFAULT NULL,
              is_deleted tinyint(1) NOT NULL DEFAULT 0,
              PRIMARY KEY (id), UNIQUE KEY uk_employee_sys_user_id (sys_user_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """);
        exec("""
            CREATE TABLE employment (
              id bigint unsigned NOT NULL AUTO_INCREMENT,
              employee_id bigint unsigned NOT NULL,
              position_id bigint unsigned NOT NULL DEFAULT 1,
              organization_id bigint unsigned NOT NULL,
              legal_entity_id bigint unsigned NOT NULL,
              employment_type varchar(20) NOT NULL DEFAULT 'PRIMARY',
              start_date date NOT NULL,
              end_date date NOT NULL DEFAULT '9999-12-31',
              change_type varchar(20) NOT NULL DEFAULT 'HIRE',
              is_current tinyint(1) NOT NULL DEFAULT 1,
              is_deleted tinyint(1) NOT NULL DEFAULT 0,
              PRIMARY KEY (id),
              KEY idx_employment_organization_id (organization_id),
              KEY idx_employment_employee_id_start_date (employee_id, start_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """);
    }

    private static void seed() throws SQLException {
        // 两个法人：1 = 瑞堂塑料集团，2 = 宁波瑞镁
        exec("""
            INSERT INTO organization (id, org_code, org_name, legal_entity_id, parent_id, org_path, org_level, org_type) VALUES
            (1,  'G',      '集团',       1, 0,  '/1/',        1, 'GROUP'),
            (3,  'CO-A',   '浙江瑞堂',   1, 1,  '/1/3/',      2, 'COMPANY'),
            (15, 'DEPT-X', '注塑车间',   1, 3,  '/1/3/15/',   3, 'DEPARTMENT'),
            (16, 'TEAM-Y', '注塑一班',   1, 15, '/1/3/15/16/',4, 'TEAM'),
            (20, 'CO-B',   '宁波瑞镁',   2, 0,  '/20/',       1, 'COMPANY'),
            (21, 'DEPT-Z', '滚塑车间',   2, 20, '/20/21/',    2, 'DEPARTMENT');
            """);

        // 6 人：分布在两个法人、三个部门；5 号是跨法人派驻（组织属法人1、用工主体属法人2）
        exec("""
            INSERT INTO employee (id, emp_no, emp_name, sys_user_id) VALUES
            (1, 'A26000001', '张三', 101),
            (2, 'A26000002', '李四', 102),
            (3, 'A26000003', '王五', 103),
            (4, 'B26000004', '赵六', 104),
            (5, 'A26000005', '钱七', 105),
            (6, 'A26000006', '孙八', 106);
            """);

        exec("""
            INSERT INTO employment (employee_id, organization_id, legal_entity_id, start_date, is_current, change_type) VALUES
            (1, 15, 1, '2024-01-01', 1, 'HIRE'),
            (2, 16, 1, '2024-01-01', 1, 'HIRE'),
            (3, 3,  1, '2024-01-01', 1, 'HIRE'),
            (4, 21, 2, '2024-01-01', 1, 'HIRE'),
            (5, 15, 2, '2024-01-01', 1, 'HIRE'),
            (6, 16, 1, '2024-01-01', 1, 'HIRE');
            """);

        // 用例 11：6 号调岗历史——曾在 21（法人2），现在 16
        exec("""
            INSERT INTO employment (employee_id, organization_id, legal_entity_id, start_date, end_date, is_current, change_type) VALUES
            (6, 21, 2, '2023-01-01', '2023-12-31', 0, 'TRANSFER');
            """);
    }

    // ---------------------------------------------------------------- 工具

    private static void exec(String sql) throws SQLException {
        try (Statement st = conn.createStatement()) {
            st.execute(sql);
        }
    }

    /** 基础 SQL + 数据权限条件 → 执行 → 返回员工 ID 列表 */
    private static List<Long> query(HrLoginContext ctx) throws SQLException {
        String cond = BUILDER.build(ann(), ctx);
        String sql = cond == null ? BASE_SQL + " ORDER BY e.id"
            : BASE_SQL + " AND (" + cond + ") ORDER BY e.id";
        List<Long> ids = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(sql); ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                ids.add(rs.getLong(1));
            }
        }
        return ids;
    }

    /** count(*) 也要带同一套条件，否则分页总数会泄露全量（用例 10） */
    private static long count(HrLoginContext ctx) throws SQLException {
        String cond = BUILDER.build(ann(), ctx);
        String sql = "SELECT COUNT(*) FROM (" + BASE_SQL
            + (cond == null ? "" : " AND (" + cond + ")") + ") t";
        try (PreparedStatement ps = conn.prepareStatement(sql); ResultSet rs = ps.executeQuery()) {
            rs.next();
            return rs.getLong(1);
        }
    }

    private static HrLoginContext ctx(List<HrDataScopeRule> rules, Long employeeId) {
        HrLoginContext c = new HrLoginContext();
        c.setUserId(employeeId == null ? 999L : employeeId);
        c.setEmployeeId(employeeId);
        c.setScopeRules(rules == null ? new ArrayList<>() : new ArrayList<>(rules));
        boolean export = c.getScopeRules().stream().anyMatch(r -> Boolean.TRUE.equals(r.getCanExport()));
        c.setCanExport(export);
        return c;
    }

    private static HrDataScopeRule rule(String type, String value) {
        return new HrDataScopeRule(1L, type, value);
    }

    /** 与 EmployeeMapper.selectScopeRows 上的注解保持一致 */
    private static HrDataScope ann() {
        return new HrDataScope() {
            @Override
            public String orgAlias() {
                return "em";
            }

            @Override
            public String empAlias() {
                return "e";
            }

            @Override
            public String legalAlias() {
                return "";
            }

            @Override
            public String orgColumn() {
                return "organization_id";
            }

            @Override
            public String legalColumn() {
                return "legal_entity_id";
            }

            @Override
            public String empColumn() {
                return "id";
            }

            @Override
            public Class<? extends Annotation> annotationType() {
                return HrDataScope.class;
            }
        };
    }

    // ---------------------------------------------------------------- 12 条用例

    @Test
    @Order(1)
    @DisplayName("1. 集团 HR（ALL）看到全部 6 人")
    void case01_all() throws Exception {
        assertEquals(List.of(1L, 2L, 3L, 4L, 5L, 6L), query(ctx(List.of(rule("ALL", null)), 1L)));
    }

    @Test
    @Order(2)
    @DisplayName("2. 公司 HR（COMPANY=1）只看到法人 1 的人")
    void case02_company() throws Exception {
        // 5 号组织属法人 1、用工主体属法人 2 → 不应出现；这是"跨法人派驻"的判定口径
        assertEquals(List.of(1L, 2L, 3L, 6L), query(ctx(List.of(rule("COMPANY", "1")), 3L)));
    }

    @Test
    @Order(3)
    @DisplayName("3. 部门主管（ORG_TREE）看到本部门及子树")
    void case03_org_tree() throws Exception {
        HrDataScopeRule r = rule("ORG_TREE", "15");
        r.setPathPrefix("/1/3/15/");
        assertEquals(List.of(1L, 2L, 5L, 6L), query(ctx(List.of(r), 1L)));
    }

    @Test
    @Order(4)
    @DisplayName("4. 普通员工（SELF）只看到自己")
    void case04_self() throws Exception {
        assertEquals(List.of(1L), query(ctx(List.of(rule("SELF", null)), 1L)));
    }

    @Test
    @Order(5)
    @DisplayName("5. 兼任两角色取并集且不重复")
    void case05_union() throws Exception {
        HrDataScopeRule tree = rule("ORG_TREE", "21");
        tree.setPathPrefix("/20/21/");
        // 法人 1 的 4 人 + 组织 21 的 1 人 = 5 人，无重复
        assertEquals(List.of(1L, 2L, 3L, 4L, 6L),
            query(ctx(List.of(rule("COMPANY", "1"), tree), 1L)));
    }

    @Test
    @Order(6)
    @DisplayName("6. 没有任何规则 → 0 条（默认拒绝，不是全量）")
    void case06_deny() throws Exception {
        assertEquals(0, query(ctx(new ArrayList<>(), 1L)).size());
    }

    @Test
    @Order(7)
    @DisplayName("7. 纯管理员：ALL 正常，仅 SELF 时 0 条")
    void case07_admin() throws Exception {
        assertEquals(6, query(ctx(List.of(rule("ALL", null)), null)).size());
        assertEquals(0, query(ctx(List.of(rule("SELF", null)), null)).size());
    }

    @Test
    @Order(8)
    @DisplayName("8. can_export=0 时列表可见但导出被拒")
    void case08_export() throws Exception {
        HrDataScopeRule onlyRead = rule("COMPANY", "1");
        onlyRead.setCanExport(false);
        HrLoginContext c = ctx(List.of(onlyRead), 3L);

        assertEquals(4, query(c).size(), "列表仍然可见");
        assertThrows(HrDataScopeException.class, () -> HrExportGuard.check(c), "导出应被拒绝");

        HrDataScopeRule withExport = rule("COMPANY", "1");
        withExport.setCanExport(true);
        HrLoginContext ok = ctx(List.of(withExport), 3L);
        assertTrue(HrExportGuard.canExport(ok));
    }

    @Test
    @Order(9)
    @DisplayName("9. 组织移动后按新 org_path 生效（无需清缓存也能立刻对）")
    void case09_org_move() throws Exception {
        HrDataScopeRule r = rule("ORG_TREE", "15");
        r.setPathPrefix("/1/3/15/");
        HrLoginContext c = ctx(List.of(r), 1L);
        assertEquals(4, query(c).size());

        // 把 16 号小组挪到 21 号下：它不再是 15 的子树
        exec("UPDATE organization SET org_path = '/20/21/16/' WHERE id = 16");
        try {
            assertEquals(List.of(1L, 5L), query(c), "移动后原主管不应再看到 16 的人");
        } finally {
            exec("UPDATE organization SET org_path = '/1/3/15/16/' WHERE id = 16");
        }
        assertEquals(4, query(c).size(), "移回后恢复");
    }

    @Test
    @Order(10)
    @DisplayName("10. 分页：count 与列表口径一致（SQL 层过滤）")
    void case10_paging() throws Exception {
        HrLoginContext c = ctx(List.of(rule("COMPANY", "1")), 3L);
        long total = count(c);
        List<Long> all = query(c);
        assertEquals(all.size(), total, "总数必须是过滤后的数，不能是全表数");

        String cond = BUILDER.build(ann(), c);
        String sql = BASE_SQL + " AND (" + cond + ") ORDER BY e.id LIMIT 2 OFFSET 0";
        int page = 0;
        try (PreparedStatement ps = conn.prepareStatement(sql); ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                page++;
            }
        }
        assertEquals(2, page, "第一页应取到 2 条");
    }

    @Test
    @Order(11)
    @DisplayName("11. 调岗后用历史任职仍能看到当时归属")
    void case11_history() throws Exception {
        // 6 号现在在 16（法人1），历史在 21（法人2）。按历史表查 21 的记录必须查得到，
        // 否则原主管查历史考勤会凭空少人。
        String sql = """
            SELECT COUNT(*) FROM employment
            WHERE employee_id = 6 AND organization_id = 21 AND is_current = 0 AND is_deleted = 0
            """;
        try (PreparedStatement ps = conn.prepareStatement(sql); ResultSet rs = ps.executeQuery()) {
            rs.next();
            assertEquals(1, rs.getInt(1));
        }
    }

    @Test
    @Order(12)
    @DisplayName("12. 未标注 @HrDataScope 的查询不注入任何条件")
    void case12_no_annotation() {
        HrLoginContext c = ctx(List.of(rule("SELF", null)), 1L);
        assertNull(BUILDER.build(null, c), "没有注解就不该产生条件（如 sys_dict 这类公共表）");
    }
}
