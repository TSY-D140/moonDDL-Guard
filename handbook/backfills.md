# Bounded INSERT SELECT preflight

Version 0.25.0 accepts an explicit target list of 1–32 distinct columns and a SELECT of the same width from one ordinary table (optional schema/alias), or a literal VALUES source with an explicit alias/column list and at most 100 equal-width rows. No joins or derived SELECTs are accepted. Projections support existing bounded DML scalars, aliases and top-level argument-free `gen_random_uuid()`; the latter is not added to the existing VALUES seed or UPDATE profiles. Built-in resolution is conditional, not certified. WHERE supports existing DML predicates. Existing simple-column ON CONFLICT DO NOTHING/DO UPDATE and RETURNING profiles are retained. Total token/depth bounds remain 1024/32.

General CTEs, UNION, DISTINCT, grouping/aggregates/windows, ORDER/LIMIT/OFFSET, query locks, SELECT *, arbitrary functions/subqueries, target aliases, OVERRIDING, expression/partial/named conflict arbiters and unknown active AST fields reject the **entire** statement as incomplete. No clauses are discarded. Even WHERE FALSE does not certify target-side defaults/triggers or lock acquisition.

PG821 covers target ROW EXCLUSIVE and catalog/data hazards. PG823 distinguishes unbounded table-source cardinality from a counted literal source; PG824 covers retry/duplicate/concurrent-write risks; PG825 identifies a retained stronger source lock. PG803 still covers a retained target lock and PG804 active/implicit/unknown transaction scope. Conflict and RETURNING findings remain. No query is run, checkpoint invented or cardinality inferred from WHERE. A random UUID is not an idempotency key.

```sh
moon run engine/cli -- specimens/corpus/umami/4.sql --transaction=autocommit --delivery=statements --json
moon run engine/cli -- specimens/backfill/calcom-permissions.sql --transaction=autocommit --delivery=statements --json
moon run --deny-warn checks/backfill.mbtx
```

Both real files return 1 and retain original SQL. Their sources and licenses are linked in `specimens/backfill/README.md`. For deployment, first measure source cardinality/plan, test the full schema's constraints/triggers/RLS, choose stable retry/checkpoint keys, budget WAL/locks, and validate runner transaction boundaries. This library reviews the submitted SQL; it does not implement a batching or migration executor. Older reports involving newly assessed statements require regeneration for strict replay.
