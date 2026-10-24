# MoonDDL Guard

Static preflight for PostgreSQL index and CHECK-constraint migrations, exposed as a MoonBit library and a file CLI. It reviews existing SQL before your migration runner executes it.

The current profile targets PostgreSQL 18 named B-tree `CREATE [UNIQUE] INDEX [CONCURRENTLY] [IF NOT EXISTS]` statements, including a bounded expression/predicate subset and `INCLUDE` columns. It reports write blocking, transaction incompatibility, expression immutability, conditional uniqueness and unchecked database preconditions. Explicit `lock_timeout` / `statement_timeout` settings are tracked through session, transaction-local, commit and rollback scopes. Every unsupported statement is retained and prevents a complete verdict.

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

The [Umami specimens](specimens/upstream/README.md) are real, unmodified, commit-pinned SQL with their MIT license. The 17-index migration yields 17 PG101 findings. A second mixed migration remains incomplete and still reports its final supported indexes. The executable `.mbtx` check verifies these CLI behaviors and persisted-report round trips without a database.

Limits: 262144 UTF-16 source code units, 512 executable statements, 256 tokens per assessed index, 32 nested key-expression parentheses, 32 total key/payload columns (standard PostgreSQL build), and 8388608 UTF-16 code units for report decoding. Larger/unsupported input receives an explicit incomplete/error result; SQL is never truncated or rewritten.

Version 0.5.0 assesses `SET [SESSION|LOCAL] lock_timeout|statement_timeout` with a deliberately bounded exact-duration grammar. It reports ineffective LOCAL settings, disabled/unknown budgets and conflicting lock/statement budgets. Settings apply to subsequent statements on the same session; no inherited default is assumed. Read [timeout scope and runnable examples](handbook/timeouts.md) for supported conversions, limits and diagnostics.

Version 0.6.0 also reviews index replacement/removal: [DROP INDEX workflow](handbook/removal.md), blocking locks, concurrent-drop restrictions and unchecked catalog dependencies. The public analysis API is unchanged.

Version 0.7.0 adds [staged CHECK validation review](handbook/constraints.md), including the stronger-lock retention hazard when ADD and VALIDATE share a transaction or Simple Query message.

Planned: additional PostgreSQL versions, broader constraint operations and database integration tests.

Apache-2.0. Third-party dependency and fixture terms are recorded in [SOURCES.md](SOURCES.md).
