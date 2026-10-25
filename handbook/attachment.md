# Attach a prebuilt unique index

The profile supports one named `ALTER TABLE [ONLY] table ADD CONSTRAINT name UNIQUE|PRIMARY KEY USING INDEX index_name` action, with at most 256 tokens. Table names may be schema-qualified; the index and constraint names are unqualified. Deferrability options, unnamed additions, extra ALTER actions and other suffixes are unassessed rather than discarded.

PG407 reports ACCESS EXCLUSIVE during attachment even if the preceding index was built concurrently. PG408 retains catalog eligibility checks: the index must be valid and eligible, unique, B-tree, use default ordering, have no predicate/expression keys, belong to this table and not already be owned by another constraint. This PostgreSQL form is unavailable for partitioned tables. The tool does not infer eligibility from another CREATE statement in the file: IF NOT EXISTS, prior failures and existing catalog objects can make that inference unsafe.

PG409 records index renaming/ownership transfer: dropping the constraint also drops its index. PG410 separately warns that PRIMARY KEY attachment can scan nullable key columns while establishing NOT NULL. A prebuilt unique index is not proof that columns have NOT NULL metadata.

See [column nullability preflight](nullability.md) for explicit SET/DROP NOT NULL and catalog-proof limitations.

The attachment's strong table lock participates in the existing retention analysis: a following VALIDATE in the same transaction may retain it (PG405); commit/rollback ends the lock, while savepoint rollback removes only later acquisitions. Timeouts, source retention, SARIF and strict replay apply without a new public API.

```sh
moon run engine/cli -- specimens/attach-unique.sql --transaction=autocommit --delivery=statements
```

The complete review returns 1 for the cutover lock. Both build and attachment report their 1000ms budget. Whole-file delivery additionally reports PG201 for the concurrent build. No catalog inspection, SQL execution or rollback SQL is generated.

Behavior follows PostgreSQL 18 [ADD constraint USING INDEX](https://www.postgresql.org/docs/18/sql-altertable.html). The specimen and tests are project-owned Apache-2.0; no upstream code/tests are copied. Searches for `MoonBit USING INDEX migration review` and `MoonBit migration NOT NULL preflight` found no evidence changing the established schema-plan/migrate complementary boundary, but cannot exclude unpublished/unindexed projects.
