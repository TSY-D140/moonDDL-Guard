# Identity, serial and generated-column transitions

Supports ADD COLUMN integer-type GENERATED ALWAYS|BY DEFAULT AS IDENTITY; serial/bigserial/smallserial; and supported-type GENERATED ALWAYS AS (bounded scalar expression) [STORED|VIRTUAL], optionally followed by NOT NULL. PostgreSQL 18 defaults omitted storage to VIRTUAL. IF NOT EXISTS is retained as a catalog/no-op condition. Virtual columns reject custom/quoted/qualified types in this profile because their built-in requirements cannot be established. Sequence options, multiple constraints/actions and unknown functions remain incomplete.

Existing columns support ADD GENERATED ... AS IDENTITY, SET GENERATED ALWAYS|BY DEFAULT, DROP IDENTITY [IF EXISTS], SET EXPRESSION AS (...), and DROP EXPRESSION [IF EXISTS]. These forms are deliberately distinguished from adding a new identity column: changing existing identity attributes affects future writes and does not backfill existing values. Arbitrary sequence options/restarts and unknown generation clauses remain unassessed.

PG501 retains the ACCESS EXCLUSIVE budget. PG514 covers new identity/serial/stored-expression column rewrites; PG515 covers owned sequences, explicit-value acceptance and the absence of a uniqueness/gap-free guarantee. PG516 distinguishes virtual read-time computation from a rewrite. PG517 covers existing-column identity transitions, sequence synchronization and future inserts. PG518 reports conditional stored rewrite/virtual-read behavior for expression replacement without inventing the old generation kind. PG519 covers loss of automatic recomputation while retaining stored values; PostgreSQL does not support DROP EXPRESSION for virtual columns. Catalog eligibility, immutable function/operator resolution, generated-column references, table kind and existing data remain prerequisites.

The default-expression profile also accepts no-argument gen_random_uuid(), uuidv4() and uuidv7() as standard built-in volatile defaults. Adding such a column can rewrite old rows; setting the same default on an existing column does not backfill or rewrite those rows. Qualified/overloaded resolution and user functions still need inspection.

```sh
moon run engine/cli -- specimens/generated-columns.sql --transaction=autocommit --delivery=statements --json
```

Returns 1 with distinct rewrite/virtual/identity-transition diagnostics. Tests cover malformed combinations, unsupported options, stored-versus-virtual distinctions, rollback, baseline and report/SARIF replay. The PostgreSQL harness compares actual relation file nodes and generated values, then checks retained base values after expression removal. Sources: PostgreSQL 18 [ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html), [CREATE TABLE](https://www.postgresql.org/docs/18/sql-createtable.html) and [UUID functions](https://www.postgresql.org/docs/18/functions-uuid.html). Code/tests/specimen are project-owned Apache-2.0; no upstream source/tests are copied.
