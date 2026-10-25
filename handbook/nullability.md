# Review column nullability changes

The profile assesses one `ALTER TABLE [ONLY] table ALTER [COLUMN] name SET|DROP NOT NULL` action per statement, with the shared 256-token limit. Table names may be schema-qualified; column names are unqualified. Empty quoted identifiers, extra actions, IF EXISTS, SET DEFAULT, SET NULL, NOT VALID and unknown suffixes remain incomplete. Rejecting a profile extension does not mean PostgreSQL rejects that extension.

PG411 reports ACCESS EXCLUSIVE held until transaction end. For SET, PG412 warns of a possible existing-row scan under that lock. PostgreSQL can skip the scan if a valid retained CHECK proves non-nullness; no catalog proof is inferred merely because this file contains ADD/VALIDATE text. PG414 asks for column/data, primary-key and ancestry checks. For DROP, PG413 records removal of the NOT NULL requirement and the risk of future null data making reversal expensive; other constraints may still reject nulls. Parent/partition or primary-key requirements can make the drop fail.

Both operations participate in timeout reporting and strong-lock retention at a following VALIDATE. Commit/rollback releases tracked locks; savepoint rollback restores the earlier set. Unsupported SQL still invalidates scope knowledge. No schema/data mutation, proof of scan elimination, migration execution or automatic rollback SQL is provided.

```sh
moon run engine/cli -- specimens/non-null.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/non-null.sql --transaction=autocommit --delivery=simple-query
```

The first returns 1 with explicit lock/scan/catalog preconditions and three 1000ms budgets. Whole-file submission additionally warns that the CHECK addition's stronger lock may persist during validation. The CLI and library reuse the normal report, SARIF, replay and baseline gates. A baseline cannot hide incomplete input or a newly introduced nullability warning.

Rules follow PostgreSQL 18 [ALTER TABLE nullability and lock rules](https://www.postgresql.org/docs/18/sql-altertable.html). The specimen/tests are project-owned Apache-2.0 code, not copied production migrations or upstream tests. The schema-plan/migrate complement remains unchanged: this reviews existing SQL and does not generate or execute schema plans.
