# Foreign-key rollout preflight

Supported: a single `ALTER TABLE [ONLY] table ADD [CONSTRAINT name] FOREIGN KEY (columns) REFERENCES table [(columns)] [MATCH SIMPLE|FULL] [ON DELETE action] [ON UPDATE action] [DEFERRABLE|NOT DEFERRABLE] [INITIALLY IMMEDIATE|DEFERRED] [NOT VALID]`. ON UPDATE may precede ON DELETE; duplicate actions are rejected. Actions are NO ACTION, RESTRICT, CASCADE, SET NULL and SET DEFAULT. Lists contain 1–32 distinct identifiers; explicit referenced lists must have the same length. MATCH PARTIAL, action column subsets, PERIOD, NOT ENFORCED and combined ALTER actions remain incomplete with the original SQL retained. The existing 256-token bound applies.

PG415 reports SHARE ROW EXCLUSIVE on **both** tables, retained until transaction end. PG416 distinguishes immediate historical-row validation from PG417's NOT VALID rollout. NOT VALID still enforces subsequent writes; it is not a lock-free or unchecked-write mode. PG418 requires catalog inspection for referenced uniqueness, compatible types, privileges, partitions and supporting indexes; PostgreSQL does not automatically index referencing columns. PG419 warns about future ON DELETE/UPDATE CASCADE data effects. PG420 covers SET NULL/DEFAULT and deferred-check preconditions.

VALIDATE retains its SHARE UPDATE EXCLUSIVE/catalog diagnostic (PG404), plus PG422: if the actual constraint is a foreign key, the referenced table needs ROW SHARE. We do not fabricate the constraint type or reference target from earlier SQL: inherited/pre-existing metadata is unknown. PG421 identifies a retained foreign-key ADD lock on the table being validated, while PG405 identifies the stronger ACCESS EXCLUSIVE class. The lock tracker never downgrades a stronger lock; it covers both FK targets and restores lock classes after savepoint rollback. Unknown SQL invalidates certainty. Aliases, search_path equivalence, descendants and locks inherited on entry still require inspection.

```sh
moon run engine/cli -- specimens/foreign-key-phases.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/foreign-key-phases.sql --transaction=autocommit --delivery=simple-query
```

Both return 1 for the ADD locks. The second additionally emits PG421: putting ADD and VALIDATE in one query does not release the earlier locks. This is a complete pre-execution workflow, not a migration executor or orphan-row query generator. The example is project-owned Apache-2.0, not a production migration. Rules follow [PostgreSQL 18 ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html), particularly ADD FOREIGN KEY, VALIDATE and Notes.
