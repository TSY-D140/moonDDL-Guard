# Index replacement and removal

The profile assesses named `DROP INDEX [CONCURRENTLY] [IF EXISTS] name [, ...] [CASCADE|RESTRICT]`, with up to 32 optionally schema-qualified names and 256 tokens. Unknown clauses remain incomplete. Concurrent removal permits only one name, forbids CASCADE and cannot run in a transaction block. Known incompatible options emit PG111; unknown execution context emits PG207 and makes the review incomplete.

Ordinary removal emits PG109 for its ACCESS EXCLUSIVE table lock. CASCADE emits PG112 for dependent-object removal. Every drop retains PG110 catalog preconditions: ownership, constraint dependencies, partition status, replacement validity and query coverage are not inspected. IF EXISTS suppresses a missing-object error, not these preconditions. No SQL is executed or automatically rewritten.

```sh
moon run engine/cli -- specimens/replace-index.sql --transaction=autocommit --delivery=statements
```

This returns 0 with advisories, including the explicit 1000ms lock budget at both index operations. Whole-file Simple Query delivery instead reports transaction conflicts for both concurrent operations. The specimen is project-owned. Rules follow PostgreSQL 18 [DROP INDEX](https://www.postgresql.org/docs/18/sql-dropindex.html), under the PostgreSQL documentation/license terms; no upstream implementation or tests were copied.
