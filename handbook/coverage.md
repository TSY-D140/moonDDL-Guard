# Core-risk coverage and reproduction

The [bootstrap profile](bootstrap.md) adds CREATE TABLE with bounded ordinary/generated definitions and FK referenced-table lock tracking, plus VALUES/DEFAULT seed INSERT and simple conflict workflows. See `engine/create_table_test.mbt`, `engine/seed_insert_test.mbt`, `specimens/bootstrap.sql` and server assertions in `checks/postgres.mbtx`. Unsupported creation/query/storage/conflict options remain incomplete, with original source retained.

The 0.13.0 bounded PostgreSQL 18 profile covers all five risk categories requested in the October 28 review. This table documents implemented behavior, not complete PostgreSQL syntax support or a deployment-safety certificate.

| Review concern | Implementation and diagnostic evidence | Boundary/regression evidence | Runnable workflow |
| --- | --- | --- | --- |
| Foreign keys | `foreign_key.mbt`, PG415–422: immediate/deferred old-row checks, both table locks, actions, retained write-blocking locks | `foreign_key_test.mbt`: composite/omitted referenced keys, action grammar, invalid lists, rollback, stronger-lock precedence, strict report/delta replay | `specimens/foreign-key-phases.sql` |
| Column type changes | `column_change.mbt`, PG501/509–511: USING, data/default conversion, unknown binary-coercion exceptions, dependencies/statistics | `column_change_test.mbt`: supported casts/scalars, malformed types, rejected unknown expressions, rollback and budgets | `specimens/column-changes.sql` |
| Table rewrites | PG502–505/509/512: nonvolatile versus volatile ADD defaults, unknown domains, possible type rewrite, future default versus backfill | Tests distinguish no-rewrite conditions, forced volatile-default semantics and unknown old-type conditions; no invented schema proof | Same column specimen; PostgreSQL harness checks relation file-node changes |
| New column defaults | PG501–508: literals, stable/volatile built-ins, NOT NULL and IF NOT EXISTS conditions | Typemod limits, unsupported identity/generated/array/extra actions, recovery after unsupported input | Column specimen and the unmodified real Umami mixed migration |
| Destructive DDL | `destructive.mbt`, PG601–607: DROP TABLE/COLUMN/CONSTRAINT, CASCADE, TRUNCATE, owned indexes, identity/trigger/snapshot conditions | `destructive_test.mbt`: conflicting/malformed clauses, target limits, savepoint release/rollback, deterministic JSON/SARIF/delta | `specimens/destructive.sql`; real Umami column drops |

All files above are under `engine/` unless otherwise qualified. Public entry points are the existing `review_sql`, report/export and comparison methods in `engine/pkg.generated.mbti`. New operations do not expose third-party ASTs or add a migration executor. Tracked table/schema identities now reject identifiers beyond 63 UTF-8 bytes, including formerly accepted ALTER names, instead of risking server-truncation aliases. Exact input grammars and diagnostic meanings are in [foreign keys](foreign-keys.md), [columns](column-changes.md) and [destructive changes](destructive.md).

## Three complete adoption scenarios

1. An order service adds a customer foreign key. Submit existing SQL and actual runner context, review the two table locks and NOT VALID data condition, separate ADD/VALIDATE transaction boundaries, verify catalog/data in a test database, then deploy using the existing runner. Whole-file submission additionally warns about retained write-blocking locks.
2. A team adds order timestamps/status and changes money precision. Compare constant/stable/volatile default diagnostics and USING conversion conditions, inspect the old schema and representative values, revise the rollout/backfill plan, then rerun the same preflight. Static review never assumes the old type or generates a data backfill.
3. A release removes legacy columns/constraints and retired tables. Review data loss, owned-index removal and CASCADE scope, verify backups/dependencies, persist the report, and use a baseline to gate newly introduced risks in CI. Unsupported SQL always keeps the current result incomplete, even with a baseline.

## Offline verification, without private infrastructure

Use the pinned stable compiler/core `0.10.17+d971670cd` and moon `0.1.20261023`:

```sh
moon fmt --check
moon info
git diff --exit-code -- engine/pkg.generated.mbti engine/cli/pkg.generated.mbti
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon run --deny-warn checks/examples.mbtx
moon run --deny-warn checks/postgres.mbtx --check-only
```

`checks/examples.mbtx` exercises real Umami SQL, all three new workflows, matching JSON across Wasm/Wasm-GC/JS, strict replay, context differences and existing baseline behavior. New truncation tests replay every prefix of five representative statements, checking recovery, bounded access and complete source retention. `checks/sarif-schema.mbtx` validates eleven outputs against the official OASIS 2.1.0 schema using external `curl`, Python and `jsonschema==4.25.1`; pass an explicit Python executable as the script argument if needed. This is optional external tooling, not a runtime dependency.

## PostgreSQL verification

The dedicated Ubuntu CI job starts the public `postgres:18` service and runs:

```sh
moon run --deny-warn checks/postgres.mbtx
```

Set PGHOST/PGPORT/PGUSER/PGPASSWORD for that disposable instance and PGDATABASE=`moonddl_guard_test`. Setup refuses existing test schemas and runs atomically; after successful setup, each case rolls back its own transaction and cleanup removes the owned schema. Cases inspect foreign-key validation/catalog flags and actual locks, constant/stable versus volatile ADD rewrites, a known int4-to-int8 rewrite, DROP-owned index/dependent-view behavior, and TRUNCATE/sequence savepoint recovery. The harness does not claim every possible lock schedule or PostgreSQL feature was exercised. A real server run is required: `--check-only` proves only MoonBit script compilation.

The local Windows Docker daemon is unavailable, so no local server execution is claimed. Windows-native also lacks a C compiler. Remote CI results for this revision must be read after an authorized push; previous successful runs do not verify the new revision. Actual results belong in [VALIDATION.md](../VALIDATION.md).
