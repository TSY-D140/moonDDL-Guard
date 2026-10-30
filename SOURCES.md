# Sources and licenses

## Runtime dependencies

- `bobzhang/sqlglot@0.1.0`: SQL tokenization and parsing, MIT. https://github.com/bobzhang/sqlglot.mbt . It is a MoonBit port of SQLGlot; its upstream notices remain in the dependency distribution. No parser source is copied into this repository.
- `moonbitlang/x@0.5.5`: file access and process exit for the CLI, Apache-2.0. https://github.com/moonbitlang/x .
- MoonBit standard library: https://github.com/moonbitlang/core ; its distribution's license applies.

## Rule references

Column SET/DROP NOT NULL behavior follows PostgreSQL 18 ALTER TABLE (nullability, scan-elision conditions, inheritance/partition and locking sections), linked in handbook/nullability.md. The implementation and property/edge tests are project-owned Apache-2.0. No database metadata, production data or external source code is copied into the implementation.

Index-backed UNIQUE/PRIMARY KEY attachment follows PostgreSQL 18 ALTER TABLE, including ownership transfer, catalog eligibility, partition restrictions and nullable-key scans. Exact links and search limitations are in handbook/attachment.md; new code, examples and tests are project-owned Apache-2.0.

Savepoint handling follows PostgreSQL 18 SAVEPOINT, ROLLBACK TO, RELEASE SAVEPOINT, the multi-statement protocol and lock-lifetime documentation linked in handbook/savepoints.md. Implementation and tests are project-owned Apache-2.0, without copied upstream code. The existing review layer remains complementary to schema-plan and migrate; this adds no schema generation or migration execution.

- PostgreSQL 18 CREATE INDEX: https://www.postgresql.org/docs/18/sql-createindex.html . Ordinary index builds block writes; IF NOT EXISTS is not a definition/validity check; uniqueness is a database-state precondition.
- PostgreSQL 18 protocol: https://www.postgresql.org/docs/18/protocol-flow.html#PROTOCOL-FLOW-MULTI-STATEMENT . Execution grouping changes transaction semantics.
- PostgreSQL 18 expression and partial-index semantics: https://www.postgresql.org/docs/18/indexes-expressional.html and https://www.postgresql.org/docs/18/indexes-partial.html . `specimens/advanced.sql` is a project-owned example illustrating those documented rules; it is not an upstream production migration.

The rule implementation and project-owned boundary tests are written for this repository. No Squawk, Strong Migrations or Unison implementation/test source has been copied. These projects informed the demand research, not an originality or performance claim.

## Timeout rule references

Index removal rules follow [PostgreSQL 18 DROP INDEX](https://www.postgresql.org/docs/18/sql-dropindex.html). The replacement specimen and boundary tests are project-owned Apache-2.0 material; no upstream code/tests were copied.

Timeout behavior follows PostgreSQL 18 [SET](https://www.postgresql.org/docs/18/sql-set.html), [client defaults](https://www.postgresql.org/docs/18/runtime-config-client.html), [setting parameters](https://www.postgresql.org/docs/18/config-setting.html) and the [GUC conversion source](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/utils/misc/guc.c), checked on 2026-10-25. PostgreSQL source is under the [PostgreSQL License](https://www.postgresql.org/about/licence/); no source or upstream tests are copied. The exact-duration subset deliberately rejects conversions requiring PostgreSQL rounding. `specimens/bounded-lock.sql`, `specimens/local-timeout.sql` and timeout tests are project-owned examples/tests under Apache-2.0, derived from the documented behavior rather than copied fixtures.

## Ecosystem boundary

New-table and seed-data review follows PostgreSQL 18 CREATE TABLE and INSERT (https://www.postgresql.org/docs/18/sql-createtable.html and https://www.postgresql.org/docs/18/sql-insert.html), checked 2026-10-30. Bounds, token/active-AST validation, FK lock tracking, conflict/retry diagnostics, examples and tests are project-owned Apache-2.0. No upstream implementation/test is copied; this does not introduce schema generation or SQL execution.

CHECK staging and lock-retention rules follow PostgreSQL 18 [ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html) and [CHECK constraints](https://www.postgresql.org/docs/18/ddl-constraints.html#DDL-CONSTRAINTS-CHECK-CONSTRAINTS). The specimen/tests are project-owned Apache-2.0 material. Rechecked schema-plan and migrate on 2026-10-25: schema diff/generation and migration execution remain separate boundaries from reviewing existing SQL. Searches included `MoonBit SQL migration review DROP INDEX NOT VALID SARIF` and `site:mooncakes.io sarif`; incomplete indexing and unpublished projects remain uncertainties, so no ecosystem-uniqueness claim is made.

https://github.com/kath61105/moon-schema-plan compares schema models and generates SQL; its safety model explicitly does not guarantee lock/performance behavior and its scope excludes SQL parsing. https://github.com/moonbit-community/migrate executes migrations. MoonDDL Guard adds pre-execution review of existing SQL rather than schema diff, SQL rendering, or a migration runner.

The research covered Mooncakes, GitHub, awesome-moonbit and moonbit-community. It cannot establish ecosystem uniqueness or exclude unpublished projects.

Rename review follows PostgreSQL 18 ALTER TABLE/ALTER INDEX and the published Squawk renaming-table/renaming-column rules and Strong Migrations rename-cutover guidance, rechecked 2026-10-30. No source/tests were copied. Rename implementation, boundary tests, rollback verification and specimen are project-owned Apache-2.0. Index names are not silently treated as owning-table identities.

Data-migration analysis and the limited-SELECT-CTE profile follow PostgreSQL 18 UPDATE/DELETE/explicit-locking documentation, including UPDATE FROM multiplicity and the documented CTE batching workflow. Strong Migrations' backfill guidance informed the transaction/batch review but explicitly does not implement dangerous-backfill detection. No upstream implementation/tests are copied. New profile code/tests, a matching disposable schema for the existing MIT Umami migration, batch SQL and semantic assertions are project-owned Apache-2.0. The original Umami SQL/license remain unchanged.

Direct key-constraint rules follow PostgreSQL 18 ALTER TABLE and CREATE TABLE, including NULLS DISTINCT/NOT DISTINCT, primary-key requirements and deferrable/ON CONFLICT conditions. The rule, tests, fixture and live-server assertions are project-owned Apache-2.0; no upstream implementation/test code is copied.

Generated/identity/serial and generation-transition rules follow PostgreSQL 18 ALTER TABLE, CREATE TABLE and UUID Functions, checked 2026-10-30. PostgreSQL 18 defaults generated storage to VIRTUAL; stored/identity additions and volatile UUID defaults have different rewrite behavior from changing existing identity/default metadata. New rule code, tests, server assertions and specimen are project-owned Apache-2.0; no upstream implementation/tests are copied.

## Upstream specimens and verification tooling

Baseline comparison and its property tests are project-owned Apache-2.0 code. The end-to-end check copies the licensed Umami SQL to _build and appends a project-owned example to verify new-finding gating; the original fixture is retained unmodified.

SARIF export follows the [OASIS SARIF 2.1.0 standard](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html) and its versioned schema; schema verification downloads an unmodified external schema at runtime and does not vendor it. OASIS notices and IPR terms are linked in the standard. The generator/tests are project-owned Apache-2.0 code. Optional validation uses [jsonschema 4.25.1](https://pypi.org/project/jsonschema/4.25.1/), MIT, as an external CLI; none of its source is copied. GitHub's official SARIF documentation informed paths/completion handling, without an upload-compatibility guarantee.

`specimens/upstream/indexes.sql` and `mixed.sql` are unmodified Umami migrations, commit `559e3c607c23d2c72d9bd4f6481bda428255323c`, copyright Umami Software, Inc., MIT. Exact source URLs and the full upstream license accompany the files. They are examples from a real project, not a claim that this tool has reviewed Umami's complete schema or deployment process.

`checks/examples.mbtx` uses `moonbitlang/async@0.22.5` for shell-free subprocess orchestration (Apache-2.0, https://github.com/moonbitlang/async) and `moonbitlang/x@0.5.5` for a local report file. The script passes command arguments as separate values and is not a shell script. CI uses the community `hustcer/setup-moonbit` action to install the pinned official compiler/core distribution; no action source is copied here.

## Expanded migration rules (2026-10-28)

Foreign-key addition, reference/action/null semantics, validation locks, column defaults/type conversion, domain/volatile-default rewrite conditions, DROP COLUMN/CONSTRAINT and statistics/dependency rules follow [PostgreSQL 18 ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html), especially its Notes, and [Modifying Tables](https://www.postgresql.org/docs/18/ddl-alter.html). Table removal and truncation follow [DROP TABLE](https://www.postgresql.org/docs/18/sql-droptable.html) and [TRUNCATE](https://www.postgresql.org/docs/18/sql-truncate.html). No PostgreSQL implementation or upstream test code is copied. New rule code, boundary/property tests, order-service SQL examples, the PostgreSQL semantic harness and handbook pages are project-owned Apache-2.0. The existing MIT Umami fixtures remain unmodified; their newly assessed ADD/DROP column statements provide real upstream acceptance inputs.

The optional integration job uses the public [Docker Official PostgreSQL image](https://hub.docker.com/_/postgres), major version 18, as an external test service, and a system PostgreSQL client. Server/client software is under the [PostgreSQL License](https://www.postgresql.org/about/licence/); the container has its own component notices. Neither binaries nor image layers are redistributed in this repository. Actual execution evidence is recorded separately; a configured job alone is not proof of passing integration.

Rechecked GitHub/Mooncakes search and the existing schema-plan/migrate repositories on 2026-10-28. Keywords: `MoonBit PostgreSQL migration review foreign key DDL`, `site:mooncakes.io migration sql guard`, `site:github.com MoonBit schema plan migration PostgreSQL`. The adjacent schema-plan destructive-change gate operates on schema plans, while this extension diagnoses existing SQL's execution/lock/rewrite conditions through the same review API. migrate remains a migration execution library. Search indexing and unpublished/new projects remain uncertain; these checks do not prove ecosystem uniqueness.
