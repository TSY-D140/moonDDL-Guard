# Savepoint-aware preflight

Version 0.10.0 assesses SAVEPOINT name, ROLLBACK [WORK|TRANSACTION] TO [SAVEPOINT] name and RELEASE [SAVEPOINT] name in a known explicit transaction. A multi-statement Simple Query implicit block alone is insufficient: PostgreSQL forbids savepoints there. BEGIN inside that message establishes an explicit block.

Each savepoint captures both tracked timeout scopes and the assessed strong-table-lock set. ROLLBACK TO restores those values and removes younger savepoints, but retains the named point for repeated rollback. RELEASE removes that point and younger points without reverting their changes. Duplicate names shadow older points; releasing the newer one exposes the older one. Transaction ends, including AND CHAIN, discard all points. Rolled-back operations and their original diagnostics remain in the audit report.

The initial savepoint stack is unknown, even for an inherited active transaction. Referring to an unobserved/released point, using an unknown or non-explicit transaction, or exceeding 64 active points produces PG208 plus an incomplete verdict. Unsupported SQL discards scope knowledge. Subsequent recognized transaction ends can recover useful analysis, without making earlier incomplete input complete.

Names use the same quote-sensitive/ASCII-folded identity as tables, bounded to 63 UTF-8 bytes. Longer identifiers are rejected rather than truncated to a different identity. Cursors, PL/pgSQL exceptions, actual server errors and already-aborted transactions are not modeled; the review remains a static successful-execution-path analysis.

```sh
moon run engine/cli -- specimens/savepoint-budget.sql --transaction=autocommit --delivery=statements
```

The example returns 1 for ordinary index risks and reports 100ms before rollback, 2000ms afterward. Tests verify that locks acquired after a point are removed on rollback, while earlier locks remain. The public API is unchanged; strict report replay includes the new operations.

Rules follow PostgreSQL 18 [SAVEPOINT](https://www.postgresql.org/docs/18/sql-savepoint.html), [ROLLBACK TO](https://www.postgresql.org/docs/18/sql-rollback-to.html), [RELEASE](https://www.postgresql.org/docs/18/sql-release-savepoint.html), [implicit query blocks](https://www.postgresql.org/docs/18/protocol-flow.html#PROTOCOL-FLOW-MULTI-STATEMENT) and [lock lifetime](https://www.postgresql.org/docs/18/explicit-locking.html). Example and tests are project-owned Apache-2.0 material; no upstream implementation/tests are copied.
