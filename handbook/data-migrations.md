# Data backfill and cleanup review

Supported PostgreSQL 18 UPDATE/DELETE profiles use a named target, optional ONLY/alias, scalar assignments (up to 32), optional UPDATE FROM / DELETE USING table joins and WHERE, and scalar/column/star RETURNING (up to 32). Expressions include qualified columns, literals, arithmetic, comparisons, boolean/null tests, LIKE/ILIKE, bounded IN lists (64), BETWEEN, lower/upper/abs, COALESCE, now()/CURRENT_TIMESTAMP/CURRENT_DATE and casts to the documented built-in column types. DEFAULT is accepted only as a complete assignment value. Types, coercion/function resolution and row counts are not inferred. Each statement is limited to 512 tokens, 32 nested parentheses and 32 participating physical relation references; identifiers are bounded to 63 UTF-8 bytes.

One nonrecursive, read-only SELECT CTE is also supported: scalar selection, ordinary table joins, optional WHERE/ORDER BY, required literal LIMIT 0–100000, and optional FOR UPDATE/SHARE [NOWAIT|SKIP LOCKED]. No OFFSET, recursive/write/multiple CTEs, aggregates, general subqueries, tuple assignment, arbitrary function calls, row cursors, UPDATE/DELETE LIMIT, dialect-specific clauses or unknown active AST fields are silently accepted. CTE names are virtual source bindings, not assumed to be physical tables. A batch LIMIT does not prove target-row cardinality: the outer join must use verified unique keys and the CTE must actually restrict the target.

| Code | Review |
| --- | --- |
| PG801 | Row/table locks, WAL/replica lag, dead tuples and actual plan/cardinality need a budget; WHERE is not a batch-size proof |
| PG802 | Missing WHERE or literal WHERE TRUE can change/remove all eligible target rows |
| PG803 | Earlier DDL may retain ACCESS EXCLUSIVE/SHARE ROW EXCLUSIVE on participating target/source tables during data work |
| PG804 | Explicit/implicit or unknown-duration transactions may retain locks and old snapshots |
| PG805 | UPDATE FROM source multiplicity makes assigned source values unpredictable; DELETE USING selectivity needs inspection |
| PG806 | Catalog/data/RLS/triggers/cascades/partition movement remain unverified |
| PG807 | RETURNING may expose many rows/sensitive data and does not limit changes |
| PG810 | Duplicate canonical assignment targets are invalid, retained, exit 2 and invalidate subsequent scope certainty |
| PG811 | Limited SELECT CTE: verify progress, unique join keys, commit boundaries and SKIP LOCKED reconciliation |

```sh
moon run engine/cli -- specimens/data-migration.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/upstream/mixed.sql --transaction=autocommit --delivery=statements --json
```

Both return 1 for actionable risks. The real unmodified Umami mixed specimen now has **all nine statements assessed**, including its UPDATE FROM and RENAME COLUMN. This is a review-completeness result, not proof of safe deployment or complete schema knowledge. The project-owned batch example deliberately keeps ADD and backfill in one transaction to demonstrate PG803; deployers should separate those phases and verify data/catalog conditions. The PostgreSQL harness runs the real licensed SQL on a matching disposable schema and checks backfill values, rename preservation and removal, plus limited-CTE/DELETE behavior. Existing report/baseline/SARIF contracts are unchanged; historical rule outputs may require their producing release.

Rules follow PostgreSQL 18 [UPDATE](https://www.postgresql.org/docs/18/sql-update.html), [DELETE](https://www.postgresql.org/docs/18/sql-delete.html) and [explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html). [Strong Migrations](https://github.com/ankane/strong_migrations#backfilling-data) documents batching/throttling/separate transactions and explicitly says it does not detect dangerous backfills; this project does not claim complete coverage by that comparison. New implementations/tests are project-owned Apache-2.0. Existing Umami inputs remain MIT and unchanged.
