# Mature-tool comparison and remaining boundaries

Reviewed against [Squawk's rule catalog](https://squawkhq.com/docs/rules/) and [Strong Migrations' checks/backfill guidance](https://github.com/ankane/strong_migrations) on **2026-10-30**. This compares risk families, not identical rules, syntax coverage, database-state analysis or contest acceptance. The PostgreSQL **18** manual defines the semantics. No upstream rule implementation or test suite is copied.

| Risk family | Implemented bounded review | Evidence |
| --- | --- | --- |
| Naming cutovers | Table/column/constraint/index/type/enum renames; type schema moves; compatibility and distinct lock semantics | [Renames](renames.md), [enums](enums.md); grammar/rollback and server cases |
| Backfills and deletes | UPDATE/FROM, DELETE/USING, missing WHERE/TRUE, duplicate assignments, joins, RETURNING, one bounded SELECT CTE, retained DDL locks | [Data migrations](data-migrations.md); exact MIT Umami SQL and matching disposable schema |
| Constraint validation | FK/CHECK immediate versus NOT VALID/VALIDATE, both relation locks, actions, non-null scans | [FK](foreign-keys.md), [CHECK](constraints.md), [nullability](nullability.md); validation/lock assertions |
| Unique/primary keys | Direct blocking builds and index attachment, nullable/duplicate data, deferrability and ownership | [Direct keys](direct-keys.md), [attachment](attachment.md); duplicate/null/owned-index server assertions |
| Defaults/types/rewrites | Constant/stable/volatile ADD defaults, bounded multi-ADD with shared locks/cost, possible domains, USING conversions; future defaults versus backfill | [Columns](column-changes.md), [combined adds](combined-additions.md); schema uncertainty retained and server file-node assertions |
| Generation | New identity/serial/stored rewrites versus existing identity metadata; virtual generation/expression changes | [Generation](generated-columns.md); actual values, sequences and file nodes |
| Index changes | Named B-tree, expressions/predicates/payloads, concurrency/transaction restrictions and recovery preconditions | [Indexes](indexes.md), [removal](removal.md); unit and portable CLI cases |
| Table structure/data loss | DROP TABLE/COLUMN/CONSTRAINT, TRUNCATE, CASCADE, identity restart and owned indexes | [Destructive DDL](destructive.md); real Umami SQL and server rollback/dependency cases |
| Other object loss | Views/materialized views, sequence/type/domain/schema/extension, explicit routine signatures, trigger/policy | [Retirement](object-removal.md); exact overload, dependent column/default and non-bypass RLS tests |
| Enum evolution | New definitions, added-label commit visibility, comparison order and textual compatibility | [Enums](enums.md); actual pre-commit failure and committed-use success |
| New tables/seeds | New versus existing table distinction, referenced FK locks, bounded VALUES/default inserts and upsert retries | [Bootstrap](bootstrap.md); AST/arity/limit and actual conflict cases |
| Execution context | Explicit/implicit/unknown scope, timeout budgets, savepoints and renamed lock identities | [Execution](execution.md), [savepoints](savepoints.md), [timeouts](timeouts.md) |
| Review integration | Source-preserving JSON/SARIF, strict replay, occurrence-aware baseline/delta gates | [SARIF](sarif.md), [baselines](baselines.md); schema and CLI checks |

Strong Migrations documents batched backfills but explicitly says it does **not** detect dangerous backfills. This project's bounded DML analysis is verified against PostgreSQL semantics and its own tests, rather than claiming parity with nonexistent detection. WHERE or CTE LIMIT never certifies a bound on changed target rows.

## Explicit remaining gaps

| Family | Current boundary |
| --- | --- |
| Partition attach/detach, inheritance, REINDEX, CLUSTER/VACUUM FULL/REPACK, non-B-tree methods | Unassessed (exit 2); require independent lock/transaction/option semantics |
| CREATE/ALTER constrained domains, exclusion constraints, arbitrary combined ALTER | Unassessed; domain dependencies and old data cannot be inferred from a type name |
| CREATE/REPLACE VIEW/FUNCTION, routine/view options, trigger enable/disable, replica identity | Unassessed; not interchangeable with DROP review |
| CREATE/ALTER policies, RLS enable/force/disable, GRANT/REVOKE, role/database/system options | Unassessed; DROP POLICY covers only its removal behavior |
| Sequence value/options changes, extension updates, composite attributes | Unassessed; runtime/dependency contracts differ from retirement |
| General SELECT/MERGE/COPY/INSERT SELECT, arbitrary calls/subqueries, writable/recursive CTEs, procedural/psql SQL | Unassessed; supported active AST fields/expressions are whitelisted |
| Every renameable object, table schema moves, arrays/storage/collations/opclasses and arbitrary signatures | Not generally supported; per-workflow grammars remain authoritative |
| Style preferences for integer/text/time types or mandatory schema qualification | No equivalent style-policy warning claimed |
| Full PostgreSQL syntax/semantic validation and catalog/cardinality/cost/privilege/dependency proofs | Outside offline guarantees; even supported syntax retains runtime preconditions |

Unassessed active clauses retain original SQL, yield incomplete status, clear subsequent execution-scope certainty and cannot be hidden by a baseline. Earlier findings remain; explicit transaction boundaries can restore local scope knowledge without making the whole report complete. `engine/rollout_properties_test.mbt` verifies prefix replay, Unicode/CRLF source spans, cross-workflow locks, recovery and independence between calls.

## MoonBit ecosystem boundary

Rechecked [moon-schema-plan](https://github.com/kath61105/moon-schema-plan) (model diff/planning/SQL generation) and [migrate](https://github.com/moonbit-community/migrate) (upgrade/downgrade execution/history; [Mooncakes](https://mooncakes.io/docs/moonbit-community/migrate)). This release accepts existing SQL plus execution context and returns diagnostics/reports, without exposing schema models, generating migration SQL or executing migrations. It remains a complementary review layer. Search terms included `site:mooncakes.io PostgreSQL migration review MoonBit` and `MoonBit PostgreSQL migration rename lint Squawk Guard`. Indexing, private/unpublished projects and future changes prevent a uniqueness claim. Dependencies and licensed fixtures are in [SOURCES.md](../SOURCES.md).
