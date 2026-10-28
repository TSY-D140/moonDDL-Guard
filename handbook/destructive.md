# Destructive migration review

Supported: `DROP TABLE [IF EXISTS] name [, ...] [CASCADE|RESTRICT]`; `ALTER TABLE [ONLY] table DROP [COLUMN] [IF EXISTS] name [CASCADE|RESTRICT]`; `ALTER TABLE [ONLY] table DROP CONSTRAINT [IF EXISTS] name [CASCADE|RESTRICT]`; and `TRUNCATE [TABLE] [ONLY] name [*] [, ...] [RESTART|CONTINUE IDENTITY] [CASCADE|RESTRICT]`. ONLY applies per TRUNCATE target and cannot combine with `*`. Lists contain at most 32 targets; statements at most 256 tokens. Other object kinds, DML DELETE, conflicting/repeated clauses and multi-action ALTER remain unassessed, retaining their SQL and exit 2.

PG601 reports ACCESS EXCLUSIVE and composes with timeout/transaction/savepoint analysis. PG602 distinguishes table destruction, lost SQL access to column data (without immediate disk reclamation), and TRUNCATE's whole-table/descendant row removal. PG605 separately identifies constraint protection loss and removal of a constraint-owned index. Restoring a constraint can fail after subsequent invalid writes.

PG603 distinguishes dependency-object removal by DROP CASCADE from **data removal in additional referencing tables** by TRUNCATE CASCADE. PG604 requires catalog/dependency/recovery inspection: RESTRICT prevents some external cascading but does not preserve the target or owned objects; IF EXISTS only handles absence. No dependency graph, backup or object existence is invented. PG606 covers RESTART IDENTITY's sequence reset/locks. PG607 covers TRUNCATE-specific triggers and old-snapshot semantics. PostgreSQL can roll back TRUNCATE and DDL in a transaction; diagnostics do not incorrectly label every operation irreversible. Committed data loss still needs an actual recovery source.

```sh
moon run engine/cli -- specimens/destructive.sql --transaction=autocommit --delivery=statements --sarif
```

Returns 1. Original SQL, source positions, actions and severities remain available in the retained SARIF review; baseline gates can acknowledge known findings but cannot suppress unsupported input. The example is illustrative, project-owned Apache-2.0. The real unmodified Umami mixed migration also exercises column deletion. Sources: PostgreSQL 18 [ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html), [DROP TABLE](https://www.postgresql.org/docs/18/sql-droptable.html) and [TRUNCATE](https://www.postgresql.org/docs/18/sql-truncate.html).
