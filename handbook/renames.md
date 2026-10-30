# Review renames across a migration

Supported: `ALTER TABLE [IF EXISTS] [ONLY] table RENAME [COLUMN] old TO new`, `RENAME CONSTRAINT old TO new`, `ALTER TABLE [IF EXISTS] table RENAME TO new`, and `ALTER INDEX [IF EXISTS] index RENAME TO new`. ONLY is not accepted for table/index rename. Source relation names may have one schema qualifier; each identifier is nonempty and at most 63 UTF-8 bytes. Destination names are unqualified. Extra clauses/actions and other object kinds remain incomplete rather than being discarded.

PG701 reports ACCESS EXCLUSIVE for table/column/constraint rename. PG704 separately reports index rename's SHARE UPDATE EXCLUSIVE, with unknown owning-table/dependent-tooling conditions; it does not invent a table identity for an index. PG702 covers applications, prepared SQL, caches and rolling releases using old names. PG703 retains existence, collisions, descendant and dependent-name checks. A metadata rename does not imply a table or index rebuild, nor automatic rewriting of application SQL.

Table rename transfers the tracked relation lock to its new lexical key, preserving an explicit schema and quoted case. It is then visible to a subsequent VALIDATE or data migration under the new name. Savepoint rollback restores the previous key/lock map, while RELEASE retains the rename. No catalog aliases or search_path equivalence are inferred. IF EXISTS findings are conditional on the object existing.

```sh
moon run engine/cli -- specimens/rename.sql --transaction=autocommit --delivery=statements
```

Returns 1 and reports a retained ACCESS EXCLUSIVE during validation of `purchases`. The Umami specimen's real RENAME COLUMN and [UPDATE FROM](data-migrations.md) are now assessed together. Existing JSON/SARIF, replay, baseline and timeout workflows apply to these operations. Rules follow PostgreSQL 18 [ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html) and [ALTER INDEX](https://www.postgresql.org/docs/18/sql-alterindex.html), and the application-cutover rationale in [Strong Migrations](https://github.com/ankane/strong_migrations#renaming-a-column). New code, tests and illustrative SQL are project-owned Apache-2.0; no upstream implementation/test source was copied.
