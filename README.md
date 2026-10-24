# MoonDDL Guard

Static preflight for PostgreSQL index migrations, exposed as a MoonBit library and a file CLI. It reviews existing SQL before your migration runner executes it.

The first profile targets PostgreSQL 18 and named, plain-column `CREATE [UNIQUE] INDEX [IF NOT EXISTS]` statements. It reports write blocking and unchecked uniqueness/existing-index preconditions. Every unsupported or malformed statement is retained in the report and prevents a complete verdict. Concurrent indexes and transaction analysis are the next capability.

## Run

Use the current stable MoonBit toolchain. From the repository root:

```sh
moon update
moon test --target wasm --deny-warn
moon run engine/cli -- specimens/ordinary.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/ordinary.sql --json
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

SQLGlot supplies PostgreSQL tokenization and syntax parsing; a separate whitelist defines what this project assesses. Parsing successfully is not evidence that an operation is supported. Expression/partial indexes, arbitrary DDL, procedural SQL, psql commands, database inspection and automatic SQL rewrites are outside this first profile.

The pure library targets Wasm, Wasm-GC, JavaScript and native. The file CLI targets Wasm through moonrun, Node.js and native. Platform support is validated by actual tests, separately from compilation. See [design](DESIGN.md) and [sources](SOURCES.md).

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

Apache-2.0. Third-party dependency and fixture terms are recorded in [SOURCES.md](SOURCES.md).
