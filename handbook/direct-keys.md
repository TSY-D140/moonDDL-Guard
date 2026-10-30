# Direct unique and primary-key additions

Supports one `ALTER TABLE [ONLY] table ADD [CONSTRAINT name] UNIQUE [NULLS [NOT] DISTINCT] (columns) [DEFERRABLE|NOT DEFERRABLE] [INITIALLY IMMEDIATE|DEFERRED]` or `PRIMARY KEY (columns)` with the same timing suffix. Names/lists use the existing 63-byte/32-column bounds; statement limit is 256 tokens. NOT VALID, INCLUDE, storage options, WITHOUT OVERLAPS, combined actions and unassessed suffixes remain incomplete rather than being ignored. Existing named USING INDEX attachment remains a separate supported operation.

PG425 reports the blocking ACCESS EXCLUSIVE/index build, with concurrent-index construction and short USING INDEX attachment as a workflow to evaluate. PG426 distinguishes primary-key non-nullness, normal unique null-distinct semantics and NULLS NOT DISTINCT duplicate-null groups. Data, collation, partition and existing-index conditions are catalog preconditions. PG427 covers deferrable failure timing and ON CONFLICT/reference-key restrictions. No existing uniqueness/nullability is invented.

```sh
moon run engine/cli -- specimens/direct-keys.sql --transaction=autocommit --delivery=statements
```

Returns 1. Locks participate in following backfill/validation and savepoint recovery, including table renames. Rules follow PostgreSQL 18 [ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html) and [CREATE TABLE constraint semantics](https://www.postgresql.org/docs/18/sql-createtable.html). Tests/specimen are project-owned Apache-2.0. The real-server harness distinguishes duplicate failure, normal-null versus nulls-not-distinct acceptance and primary-key null rejection; results are recorded by the relevant CI run.
