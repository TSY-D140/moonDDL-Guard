# MoonDDL Guard — 设计概要

状态：2026-10-24 设计基线；实现与测试状态以 README 和 VALIDATION 为准。

## 独立价值与有效边界

为已有 PostgreSQL migration SQL 提供可嵌入的静态预检：分析索引操作与显式事务、宿主事务、语句发送分组之间的关系，并输出可执行诊断和未验证前提。

最接近的 moon_schema_plan 输入前后 schema，输出计划和 SQL；它明确不解析 SQL，且 Safe 不表示无锁或性能风险。migrate 执行和记录迁移，sqlparser/sqlglot 提供语法设施。本项目补上执行前的语义审查层；不实现 schema diff、ORM、数据库驱动、迁移执行器或通用 SQL 转译。

## 三套使用案例

1. 电商 orders 表持续接收写入。开发者提交 CREATE INDEX migration，在本地或 CI 声明逐语句提交且无外层事务；工具指出普通建索引阻止并发写入的条件，建议评估 CONCURRENTLY、运行窗口与锁超时。开发者调整后再次预检，再交给既有 runner。工具不估计表大小或实际耗时。
2. 团队使用 CREATE INDEX CONCURRENTLY，但 runner 包外层事务，或一次 Simple Query 发送多个语句。调用者提供真实的发送分组和初始事务状态；工具逐语句追踪 BEGIN/COMMIT/ROLLBACK，指出禁止事务的操作及其上下文。修改 runner 配置或拆分发送后重新检查。未知上下文不会被推断为自动提交。
3. 给客户 email 增加并发唯一索引。即使事务兼容，工具仍报告重复数据和失败后 invalid index 的核查前提；IF NOT EXISTS 不能证明既有索引定义、有效状态或数据唯一性。团队在测试数据库核查数据与索引状态，随后由原有工具部署。离线报告不把这些前提当成已经验证。

## 最小公开 API（设计契约，命名随工具链验证收敛）

- review_sql(source, execution_context) -> Review：唯一的 SQL 分析入口。
- ExecutionContext 明确初始事务状态（自动提交/已在事务/未知）与发送方式（逐语句/整个 Simple Query/未知）。
- Review 包含每个语句的覆盖状态、源位置、识别出的操作、诊断和待核查前提。
- Review::to_json / to_text / exit_code：确定性输出与 CI 门禁。
- decode_report：严格解码版本化报告，支持持久化往返；拒绝未知格式和丢字段，不静默降级。

公开领域类型由根包拥有。语法依赖及扫描器隐藏在内部。接口不泄露第三方 AST。

## 首个里程碑：索引迁移预检

输入：UTF-8 SQL 文本，PostgreSQL 18 规则基线，明确执行上下文。识别 CREATE [UNIQUE] INDEX [CONCURRENTLY]、BEGIN/START TRANSACTION、COMMIT/END、ROLLBACK/ABORT 及必要的事务选项。仅对明确支持语法进行语义分析。

依赖探针先核实语法与源位置；若现有 parser 可用就复用，不自建完整 SQL parser。为了准确计入全部输入，可补充保留原文的语句边界扫描，但不接受正则表达式猜测完整 SQL。

明确不支持：运行 SQL、预测实时锁等待、检查实际数据唯一性、验证实际 invalid index、PL/pgSQL、psql 元命令、COPY 数据块、动态 SQL、自动 SQL 修复、分区表推断及其他数据库方言。未支持的语句或子句必须出现在未评估列表，并使报告不完整。

运行环境：纯分析与报告核心以 wasm、wasm-gc、js、native 为验证目标。文件 CLI 按真实宿主能力单独声明；不把编译成功当运行成功。Linux/macOS/Windows CI 执行明确支持的目标。当前本机为 Windows；其他操作系统结果只有远端 CI 执行后才算通过。

## 正确性与异常契约

- 全部输入必须计入：已分析、未支持或词法/语法错误。无全局 safe=true；无已知违规也不等于上线安全。
- BEGIN/COMMIT/ROLLBACK 的效果取决于发送分组；Simple Query 多语句隐式事务按 PostgreSQL 官方协议建模。未知执行上下文产生待确认诊断。
- 诊断带稳定编号、严重级别、语句序号、原文范围、原因及下一步操作。位置采用 UTF-16 偏移，并提供一基行列；Unicode、CRLF 和注释须测试。
- 词法输入无法可靠划界时拒绝该文件的剩余部分；不同 review 调用互不污染。可可靠划界的未知语句保留并继续分析后续语句，同时保持不完整状态。
- 不自动改写或丢弃 SQL。单/双引号、转义字符串、嵌套注释和 dollar quoting 中的分号不得被误切分。
- 报告顺序固定；JSON 使用版本标识。往返解码须保留源文、覆盖状态、前提和诊断；未知字段应拒绝，避免静默数据损失。

## 演示与可公开验证内容

首个可运行命令接受真实 .sql 文件和执行上下文，输出文本或 JSON 及退出码。文档提供普通索引、并发索引事务冲突、唯一索引前提三条端到端命令；至少一份样本来自固定 commit 的真实开源 migration，保留上游许可证与来源。

无凭据即可验证：确定性报告、规则与语句位置、未知输入拒绝、坏输入后的恢复、报告往返，以及所有已支持后端的运行结果。可选临时 PostgreSQL 18 实例可验证事务错误；未实际启动实例时必须标为未执行，不能声称数据库集成通过。

## 连贯能力路线

1. 索引迁移预检：完整库、文件 CLI、报告、真实样本、边界与属性测试、多目标 CI。
2. 约束分阶段迁移：NOT VALID / VALIDATE CONSTRAINT 与跨步骤前提，先补足 parser 支持并复核生态重叠。
3. 列与约束演进：版本明确的 NOT NULL、类型变更规则；不会静态证明的条件继续显式保留。
4. 下游集成：对已有 migration runner 提供执行上下文适配；扩展 PostgreSQL 版本矩阵和可复现数据库验证。

不以提交数规划能力。每项能力在实现、测试、文档和生成接口一起完成后才进入下一项。

## 来源与差异化证据

- https://github.com/kath61105/moon-schema-plan#safety-model
- https://github.com/moonbit-community/migrate
- https://github.com/moonbit-community/sqlparser
- https://github.com/bobzhang/sqlglot.mbt
- https://www.postgresql.org/docs/18/sql-createindex.html
- https://www.postgresql.org/docs/18/protocol-flow.html#PROTOCOL-FLOW-MULTI-STATEMENT
- https://github.com/sbdchd/squawk
- https://github.com/ankane/strong_migrations

2026-10-23 的候选审查基于 Mooncakes、GitHub、官方与社区仓库的有限检索，不宣称生态唯一或全球原创。后续引用代码和样本必须逐项记录在 SOURCES.md。
