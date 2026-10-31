# MoonDDL Guard 项目申报书

**1、项目名称：** MoonDDL Guard——基于 MoonBit 的 PostgreSQL 数据库迁移静态预检工具。

**2、项目简介：** 面向数据库开发者和应用维护团队，在执行迁移 SQL 前审查锁、事务、扫描、表重写及数据丢失风险，输出带源码位置、原因和处理建议的诊断，减少上线前反复人工审查的成本。

**3、项目方向与通用性：** 数据库开发工具与工程质量保障。提供可复用 MoonBit 库和文件 CLI，可接入不同迁移工具与 CI；直接分析已有 SQL 及真实执行上下文，与 schema 规划器、迁移执行器互补。当前支持 PostgreSQL 18 的明确语法子集，未知语句或子句保留原文并报告不完整。

**4、完整的预期使用场景：**

- 外键分阶段上线：开发者提交订单与客户关联 SQL，声明事务和发送方式；工具审查双方的锁、NOT VALID、后续验证和级联动作；团队分离提交，核实历史数据及引用条件后，通过原有迁移工具部署。
- 列变更上线：团队新增状态或时间戳列、修改金额类型；工具区分常量、稳定和易变默认值，提示重写条件、USING 转换及非空校验风险；开发者核实旧类型和样本数据，调整回填与切换步骤，再次预检。
- 旧结构清理与 CI 门禁：维护者提交删列、删约束、删表或清空临时表的 SQL；工具提示数据丢失、索引归属和 CASCADE 影响；团队核查依赖与恢复来源，保存完整报告作为基线，在 CI 中审查新增风险后再部署。

**5、核心功能与交付：** 0.21.0 已实现外键新增与验证、列类型及 USING 转换审查、默认值与表重写风险区分、DROP TABLE/COLUMN/CONSTRAINT 和 TRUNCATE 审查；已补齐表/列/约束/索引 RENAME、UPDATE/DELETE 与批量回填，增加直接主键/唯一约束、生成列、建表与种子数据、枚举及对象删除审查；同时支持索引、CHECK、非空和索引转约束、事务/保存点/超时分析，以及 JSON/SARIF、严格回放和基线比较。库、CLI、真实样本、测试和 CI 均已交付。

验证：120 组测试在 Windows、Ubuntu、macOS CI 的 Wasm、Wasm-GC、JavaScript 上通过，Linux/macOS 原生运行通过；真实 PostgreSQL 18 集成包含虚拟生成列非空校验、双会话锁超时与恢复，18 份 SARIF 输出通过 schema 校验。另有独立模块消费及发布包构建验证。Windows 原生运行尚未验证；Mooncakes 按作者决定暂不发布。[验证记录](https://github.com/TSY-D140/moonDDL-Guard/actions/runs/41197961189)

后续规划：扩展 PostgreSQL 版本、表达式和 ALTER 语法覆盖，增加可选数据库元信息证据；这些能力尚未实现。

**6、项目性质：** 独立开发的应用项目，非整项目移植。领域审查逻辑和工作流在本仓库实现，复用开源解析基础设施，不宣称生态唯一性。

**7、参考来源与许可证：** 复用 [sqlglot.mbt](https://github.com/bobzhang/sqlglot.mbt)（MIT）进行分词和解析；需求研究参考 Squawk、Strong Migrations，规则依据 PostgreSQL 官方文档。项目采用 Apache-2.0，依赖与真实 Umami 样本的来源、许可证见 [SOURCES.md](https://github.com/TSY-D140/moonDDL-Guard/blob/main/SOURCES.md)。

**8、GitHub 仓库与有效提交：** [TSY-D140/moonDDL-Guard](https://github.com/TSY-D140/moonDDL-Guard)，已有不少于 22 个实质提交，覆盖核心规则、工作流和 CI 修复，未通过空提交、重复提交或无意义拆分凑数。[提交历史](https://github.com/TSY-D140/moonDDL-Guard/commits/main)｜[功能与复现证据](https://github.com/TSY-D140/moonDDL-Guard/blob/main/handbook/coverage.md)
