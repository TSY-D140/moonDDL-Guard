# Stage CHECK validation deliberately

Supported input is a single `ALTER TABLE [ONLY] table ADD CONSTRAINT name CHECK (predicate) [NOT VALID]` action or `ALTER TABLE [ONLY] table VALIDATE CONSTRAINT name`. Names may be quoted and schema-qualified (constraint names are unqualified). Statements are bounded to 256 tokens, predicate nesting to 32; the predicate uses the same bounded scalar subset as index predicates. Foreign-key additions, unnamed checks, multiple actions, NO INHERIT, NOT ENFORCED, IF EXISTS and other ALTER clauses remain incomplete.

The workflow identifies the ADD phase's ACCESS EXCLUSIVE lock (PG401), immediate scans (PG402), deferred verification of old rows (PG403), validation's SHARE UPDATE EXCLUSIVE lock and catalog/data preconditions (PG404). CHECK passes on true or null, and function/operator types and immutability are unverified (PG406); a positive-value check is not a non-null guarantee.

PG405 warns if a preceding assessed CHECK addition to the same lexical table identity may still hold its stronger lock during validation. Explicit transaction ends release tracked locks; chained transactions start with an empty tracked lock set. Separately synchronized autocommit statements release locks between phases. A multi-statement Simple Query message keeps them even without BEGIN. Unknown SQL clears certainty and leaves the review incomplete. No claim is made about locks inherited at entry or introduced by unassessed statements.

Identity matching folds ASCII in unquoted names, preserves quoted case and keeps schema/name boundaries distinct. Unqualified and qualified names are not assumed equivalent; search_path aliases, identifier truncation, descendants and pre-existing locks require manual inspection. A VALIDATE statement may refer to a pre-existing CHECK, foreign key or not-null constraint: existence/type/enforcement/validity are catalog preconditions, not fabricated from this file. Validation can be a no-op if already valid. No migration or data repair is executed.

```sh
moon run engine/cli -- specimens/check-phases.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/check-phases.sql --transaction=autocommit --delivery=simple-query
```

Both return 1 because ADD still requires a strong lock; only whole-file delivery adds PG405. The 1000ms lock budget is reported at both phases. The example and tests are project-owned Apache-2.0 material. Rules follow PostgreSQL 18 [ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html) and [CHECK constraints](https://www.postgresql.org/docs/18/ddl-constraints.html#DDL-CONSTRAINTS-CHECK-CONSTRAINTS); no upstream code/tests are copied.
