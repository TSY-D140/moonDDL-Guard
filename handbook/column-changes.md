# Column changes, defaults and table rewrites

Supported single actions under `ALTER TABLE [ONLY] table`:

- `ADD [COLUMN] [IF NOT EXISTS] column type [DEFAULT expression] [NOT NULL]` (NOT NULL can also precede DEFAULT);
- `ALTER [COLUMN] column [SET DATA] TYPE type [USING expression]`;
- `ALTER [COLUMN] column SET DEFAULT expression` and `DROP DEFAULT`.

Built-in spelling profile: smallint/int2, int/integer/int4, bigint/int8, boolean/bool, text, uuid, json/jsonb, bytea, date, real/float4/float8, double precision, numeric/decimal, varchar/char/character [varying], timestamp/timestamptz and time/timetz. Character lengths are 1–9999, numeric precision 1–1000 and scale -1000–1000, temporal precision 0–6; TIME/TIMESTAMP accept WITH/WITHOUT TIME ZONE. Unparameterized custom/qualified/quoted type names are accepted conservatively as possible constrained domains; they do not receive a no-rewrite finding. Serial, identity and generated columns have a separate [supported single-action profile](generated-columns.md). Up to 32 ordinary additions can share one statement under the [combined-addition profile](combined-additions.md). Arrays, COLLATE, explicit NULL, extra inline constraints and arbitrary mixed ALTER actions remain incomplete.

Defaults support string/number/boolean/null literals, signed numbers, wrapping parentheses, CURRENT_TIMESTAMP, now(), transaction_timestamp(), statement_timestamp(), clock_timestamp(), random(), nextval('sequence'), gen_random_uuid(), uuidv4() and uuidv7(). General calls, casts, subqueries and arithmetic defaults are not silently simplified: they remain unassessed. USING supports the existing bounded scalar subset and a top-level PostgreSQL `::type` cast, optionally wrapped in parentheses. Arbitrary CAST/function/subquery conversions remain incomplete. Type validity, function/operator resolution, assignment compatibility and actual stored values require database inspection.

| Diagnostic | Meaning |
| --- | --- |
| PG501 | ACCESS EXCLUSIVE, even when no rewrite is needed |
| PG502 | Under standard built-in resolution, absent/nonvolatile default does not itself require a rewrite |
| PG503 | Under standard built-in resolution, a volatile ADD default requires per-row evaluation and a table/index rewrite |
| PG504 | Unknown type/domain/coercion means no no-rewrite claim |
| PG505 | Stable ADD default is evaluated for the statement, not separately for each old row |
| PG506 | New NOT NULL can reject old rows/default results or need validation; scans and rewrites differ |
| PG507–508 | Catalog/descendant preconditions; IF NOT EXISTS does not compare definitions |
| PG509 | Type change normally rewrites; binary-coercion exceptions and index equivalence require old-type/catalog evidence |
| PG510–511 | USING/data loss/default conversion, dependencies, statistics and ANALYZE preconditions |
| PG512 | SET/DROP DEFAULT affects future writes, not a data backfill |

No old schema is invented. In particular, the tool never labels `TYPE bigint` a proven no-rewrite widening conversion: the old type, conversion and existing indexes are unknown. USING does not convert the old default expression. Rewrites can need substantial temporary disk/WAL and affect old snapshots. Positive lock budgets do not eliminate those risks.

```sh
moon run engine/cli -- specimens/column-changes.sql --transaction=autocommit --delivery=statements --json
```

This returns 1 and separately diagnoses constant, stable and volatile additions, an explicit numeric conversion and a future-default change. All actions compose with timeout scopes, retained locks, savepoints, JSON/SARIF and baseline gates. The unmodified [real Umami mixed migration](../specimens/upstream/README.md) now has all nine statements assessed, including its UPDATE FROM and RENAME COLUMN. Examples/tests are project-owned Apache-2.0 unless identified as upstream. Rules follow [PostgreSQL 18 ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html) and [Modifying Tables](https://www.postgresql.org/docs/18/ddl-alter.html).
