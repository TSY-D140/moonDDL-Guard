# MoonDDL Guard

Static preflight for PostgreSQL migration SQL, exposed as a reusable MoonBit library and a file CLI. It reviews existing SQL before your migration runner executes it, preserving source locations, unsupported input and catalog conditions that need human verification.

The current release is **0.21.0**, with a bounded PostgreSQL **18** rule profile:

With `--json`, CLI input/option/replay/baseline errors return exit 2 and one JSON object: `{"format":"moonddl.error.v1","exit_code":2,"message":"..."}`. Assessed SQL (including incomplete SQL) keeps the existing report/delta format and its exit semantics. Consumers should inspect `format` before decoding a report. Plain-text invocations retain their existing diagnostics.

An [independent consumer module](integrations/consumer/main.mbt) exercises only the public library API, strict replay and a new-risk gate across Wasm/Wasm-GC/JavaScript: `moon run --deny-warn checks/consumer.mbtx`. See [adoption and publication status](handbook/adoption.md).

| Workflow | Implemented review |
| --- | --- |
| [Indexes](handbook/indexes.md), [replacement/removal](handbook/removal.md) | Named B-tree CREATE/DROP, concurrent transaction restrictions, expression/partial/covering indexes and catalog preconditions |
| [Foreign keys](handbook/foreign-keys.md) | Immediate versus NOT VALID rollout, locks on both tables, referential actions and retained write-blocking locks during validation |
| [CHECK](handbook/constraints.md), [NOT NULL](handbook/nullability.md), [index attachment](handbook/attachment.md) | Scans, strong-lock retention, existing-index ownership/eligibility and integrity conditions |
| [Column changes and rewrites](handbook/column-changes.md) | Type/USING conversion risks; constant, stable and volatile ADD defaults; unknown domains; future-default versus backfill distinction |
| [Destructive DDL](handbook/destructive.md) | DROP TABLE/COLUMN/CONSTRAINT, dependency CASCADE, owned-index loss, TRUNCATE data/identity/trigger effects |
| [Renames](handbook/renames.md) | Table/column/constraint/index compatibility and lock risks, table-name lock transfer and savepoint recovery |
| [Data migrations](handbook/data-migrations.md) | UPDATE/FROM, DELETE/USING, missing restrictions, join multiplicity, retained DDL locks, bounded SELECT CTE workflows and RETURNING |
| [Direct key constraints](handbook/direct-keys.md) | Blocking UNIQUE/PRIMARY KEY builds, NULLS NOT DISTINCT, old-data/nullability and deferrability conditions |
| [Generated columns](handbook/generated-columns.md) | Identity/serial/stored rewrites, virtual generation, existing generation changes and UUID-default distinctions |
| [Bootstrap and seed data](handbook/bootstrap.md) | New-table definitions, referenced-table FK locks, idempotence limits and VALUES/upsert conflict workflows |
| [Enum/type evolution](handbook/enums.md) | Enum creation, extension commit visibility, comparison order and value/type/schema naming cutovers |
| [Object retirement](handbook/object-removal.md) | Views/materialized views, sequences, types/domains, schemas/extensions, routine signatures, triggers and RLS policies |
| [Execution context](handbook/execution.md), [timeouts](handbook/timeouts.md), [savepoints](handbook/savepoints.md) | Explicit/implicit transactions, lock/statement budgets, partial rollback of settings and tracked lock classes |
| [Reporting](handbook/sarif.md), [baseline gates](handbook/baselines.md) | Deterministic text/JSON/SARIF, strict full-report/delta replay, occurrence-aware new-risk gates |

Every unsupported statement or clause is retained and prevents a complete verdict. No SQL is rewritten or executed. The [coverage and reproducibility matrix](handbook/coverage.md) maps implemented workflows to tests and commands; the [mature-tool comparison](handbook/rule-coverage.md) lists both implemented risk families and remaining gaps.

## Run

The verified toolchain is stable MoonBit `0.10.17+d971670cd` (moon `0.1.20261023`); CI pins its compiler and core. From the repository root:

```sh
moon update
moon test --target wasm --deny-warn
moon run engine/cli -- specimens/ordinary.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/ordinary.sql --json
moon run engine/cli -- specimens/concurrent.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/transaction.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/advanced.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/bounded-lock.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/local-timeout.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/foreign-key-phases.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/column-changes.sql --transaction=autocommit --delivery=statements --json
moon run engine/cli -- specimens/destructive.sql --transaction=autocommit --delivery=statements --sarif
moon run checks/examples.mbtx
```

The ordinary-index example intentionally returns **1**, since ordinary index creation prevents concurrent writes while it builds. Return **2** means invalid or incompletely assessed input, and **0** means no known blocking finding under the supplied context. Read advisory findings even at exit 0. None of these codes certifies production safety.

## Embed

This repository is not yet published to Mooncakes. The local module is `TSY-D140/moonddl_guard`.

```moonbit
let review = @guard.review_sql(
  "CREATE INDEX orders_customer_idx ON orders (customer_id);",
  transaction=@guard.Autocommit,
  delivery=@guard.PerStatement,
)
println(review.to_text())
```

Import `TSY-D140/moonddl_guard` with alias `guard`. The API does not expose its SQLGlot dependency's AST. Source locations use zero-based UTF-16 offsets and one-based line/column coordinates. Returned arrays are copies.

## Scope

SQLGlot supplies PostgreSQL tokenization and syntax parsing; token and active-AST whitelists define what this project assesses. Supported scalars are unqualified columns, literals, `lower`/`upper`/`abs`, parenthesized arithmetic/concatenation, comparison/boolean operators and `IS [NOT] NULL`. Keys support ASC/DESC and NULLS FIRST/LAST; B-tree is implicit or explicit. Unknown functions, casts, subqueries, aggregates, opclasses, collations, storage parameters, tablespaces and non-B-tree methods remain unassessed. See [index semantics](handbook/indexes.md). Arbitrary DDL, procedural SQL, psql commands, database inspection and automatic SQL rewrites are outside the profile.

The pure library targets Wasm, Wasm-GC, JavaScript and native. The file CLI runs through moonrun, Node.js or a native executable. Platform support is validated by actual tests, separately from compilation. See [design](DESIGN.md), [execution semantics](handbook/execution.md) and [sources](SOURCES.md).

## Development

```sh
moon fmt
moon info
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
```

The native backend requires a working C compiler. The tool does not open a database connection. There are no runtime lock-wait, data-uniqueness or deployment-safety claims.

## Persist and replay a review

```sh
moon run engine/cli -- specimens/upstream/indexes.sql --transaction=autocommit --delivery=statements --json > review.json
moon run engine/cli -- review.json --replay --json
```

Both commands return 1 for the Umami specimen's ordinary-index risks. `decode_report` and `--replay` recompute the current rule profile from the retained SQL/context and require the whole report to match. Unknown or missing fields, duplicate JSON keys (including escaped duplicates), changed diagnostics and unsupported versions are rejected. This is deterministic replay, not a signature or proof of authorship. Use the producing release when replaying historical reports whose rules differ.

The [Umami specimens](specimens/upstream/README.md) are real, unmodified, commit-pinned SQL with their MIT license. The 17-index migration yields 17 PG101 findings. The second mixed migration now has all nine statements assessed, including ADD COLUMN, UPDATE FROM, RENAME COLUMN, DROP COLUMN/INDEX and CREATE INDEX. The executable `.mbtx` check verifies these CLI behaviors and persisted-report round trips without a database; the PostgreSQL harness also executes the mixed SQL on a matching disposable schema. New order-service examples are project-owned illustrative SQL, clearly identified as such.

Limits: 262144 UTF-16 source code units, 512 executable statements, 256 tokens per assessed index/table-change statement, 32 nested expression parentheses, 32 index key/payload columns or foreign-key columns, 32 DROP/TRUNCATE targets, and 8388608 UTF-16 code units for report decoding. Tracked relation/schema names are limited to 63 UTF-8 bytes per identifier: server-side truncation must not create an untracked lock alias. Larger/unsupported input receives an explicit incomplete/error result; SQL is never truncated or rewritten.

Version 0.5.0 assesses `SET [SESSION|LOCAL] lock_timeout|statement_timeout` with a deliberately bounded exact-duration grammar. It reports ineffective LOCAL settings, disabled/unknown budgets and conflicting lock/statement budgets. Settings apply to subsequent statements on the same session; no inherited default is assumed. Read [timeout scope and runnable examples](handbook/timeouts.md) for supported conversions, limits and diagnostics.

Version 0.6.0 also reviews index replacement/removal: [DROP INDEX workflow](handbook/removal.md), blocking locks, concurrent-drop restrictions and unchecked catalog dependencies. The public analysis API is unchanged.

Version 0.7.0 adds [staged CHECK validation review](handbook/constraints.md), including the stronger-lock retention hazard when ADD and VALIDATE share a transaction or Simple Query message.

Planned: additional PostgreSQL versions, broader expression/ALTER profiles and optional catalog evidence. These are not implemented promises of complete SQL coverage.

The reusable API remains unchanged in 0.13.0; new statement operations and diagnostics extend the rule profile. `Review::to_sarif` / `--sarif` and `compare_reviews` / `--baseline=REPORT` cover the new operations too. Strict replay recomputes current rules: reports produced by an older release may need that release or regeneration. Baselines never suppress incomplete current analysis.

Optional PostgreSQL 18 semantic checks are provided in `checks/postgres.mbtx` and a dedicated CI job. They require `psql`, standard PG connection environment variables and an isolated database named `moonddl_guard_test`. The script refuses an existing `moonddl_guard_probe` schema, owns its test objects and removes them after checks. `--check-only` compiles the script without contacting a server. See [verification instructions and actual limits](handbook/coverage.md); script compilation alone is not a successful database integration run.

Apache-2.0. Third-party dependency and fixture terms are recorded in [SOURCES.md](SOURCES.md).
