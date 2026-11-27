# Opt-in offline catalog evidence

Version 0.26.0 adds partial PostgreSQL 18 snapshots and an **index-attachment evidence layer**, without connecting the library/CLI to a database. This first scope records old column type descriptions/nullability, index definition/state flags, key columns and constraint ownership. It checks the recorded preconditions for UNIQUE/PRIMARY KEY USING INDEX. It does not assess arbitrary constraints, prove type-conversion rewrite avoidance, simulate catalog changes or broaden SQL grammar.

## Export, review, replay

On the intended database, with a trusted read-only connection and explicit provenance labels:

```sh
psql -XAt -v ON_ERROR_STOP=1 -v schema=public -v source=orders-staging -v snapshot_id=before-001 -f checks/catalog-export.sql > catalog.json
moon run engine/cli -- migration.sql --catalog=catalog.json --catalog-source=orders-staging --catalog-snapshot=before-001 --transaction=autocommit --delivery=statements --json
moon run engine/cli -- saved-evidence-review.json --catalog-replay --json
```

Capture stdout as UTF-8 and preserve the review exit code. The export is one read-only SELECT using a statement snapshot, with no row data or credentials. Source/ID/timestamp are provenance claims, not authentication, age validation or proof of current state. Verify the connection, role, schema, migration point and elapsed time yourself; replace stale snapshots deliberately. A matching label cannot detect concurrent DDL. Do not publish internal object names/types without reviewing their sensitivity.

The application SQL must schema-qualify the table. Missing tables/indexes in a partial snapshot and unqualified names remain `unknown`. Earlier SQL other than known transaction/savepoint/timeout controls invalidates subsequent snapshot use, even after rollback; no successful-path catalog replay is invented. The explicit controls can still fail at runtime. `observed_pass` means only that recorded flags match this bounded checklist: ordinary table, unique/valid/ready/live/immediate B-tree, no predicate/expression/nondefault ordering/operator/collation or existing constraint ownership. It is **not** live attachment eligibility. PRIMARY KEY details distinguish recorded nullable keys from recorded NOT NULL keys. Table kinds, inheritance, permissions, other dependencies, actual data and concurrent changes still require review.

Static findings are retained byte-for-byte in the nested `review`; evidence never suppresses PG407's strong lock or any risk/coverage finding. A failed observed precondition cannot lower the exit code, and incomplete SQL stays 2. This avoids turning a stale or user-edited snapshot into a passing safety gate. `moonddl.catalog-review.v1` retains the full source/context/snapshot and evidence checks for strict recomputation. Replay checks integrity, not authenticity. Directory/SARIF/baseline combinations are rejected explicitly in this first scope; existing review/batch APIs stay unchanged.

## Library contract and bounds

`decode_catalog` → opaque `CatalogSnapshot`; `review_with_catalog` takes source, expected source/ID and execution context → opaque `CatalogReview`; both expose fresh `to_json` values, and the result has `exit_code`. `decode_catalog_review` strictly recomputes retained artifacts. The generated interface is the source for exact signatures. JSON duplicate/escaped duplicate keys, unknown/missing fields, wrong scalar types, unsupported versions, duplicate identities and inconsistent key references are rejected. Names preserve exact PostgreSQL case and have a 63 UTF-8 byte bound. No search_path or server truncation is inferred.

Limits: 1 Mi UTF-16 units per snapshot, 128 tables, 256 columns/indexes per table, 32 key columns per index; report replay uses the existing 8 Mi bound. Snapshot fields are exact as shown by `specimens/catalog/snapshot.json`; type descriptions are opaque retained text, never parsed into coercion proofs. Filesystem reads use the existing bounded UTF-8 adapter. Exporting a larger schema is rejected rather than silently truncated; scope the export deliberately. A partial snapshot cannot prove an object absent. No general constraint inventory is claimed.

The illustrative fixture is clearly labelled and requires no database:

```sh
moon run engine/cli -- specimens/catalog/attach.sql --catalog=specimens/catalog/snapshot.json --catalog-source=illustrative-orders --catalog-snapshot=before-001 --transaction=autocommit --delivery=statements --json
moon run --deny-warn checks/catalog.mbtx
```

The first returns 1 despite recorded passing preconditions. Portable tests exercise strict decode/replay, independent failing flags, wrong provenance, absent objects, prior mutations, defensive serialization, resource rejection and CLI recovery. PostgreSQL CI exports a real disposable schema, feeds it back through the CLI and checks constraint ownership changes after actual attachment. This validates the workflow, not a production database or broad catalog compatibility.
