# Risk and negative controls

`engine/contrast_test.mbt` asserts both required and forbidden findings, rather than only snapshotting diagnostics. SQL comments, Unicode/CRLF and exact report replay must preserve the verdict.

| Contrast | Required distinction | Residual risk |
|---|---|---|
| ADD nonvolatile / volatile default / SET future default | PG502 / PG503 / PG512; no cross-classified rewrite claim | All still take a strong lock; resolution is conditional |
| STORED / VIRTUAL generated column | PG514 / PG516 | Virtual NOT NULL can still validate old rows |
| UPDATE without WHERE / TRUE / FALSE / selective predicate | PG802 only for the first two | PG801 remains: WHERE is no measured cardinality proof |
| Concurrent index submitted separately / grouped Simple Query | PG201 only for the latter | Failure cleanup/catalog checks remain |
| CHECK immediate / NOT VALID; validation separate / grouped | Initial-scan and retained-lock diagnostics differ independently | NOT VALID still locks and checks new writes; CHECK permits NULL |

The PostgreSQL 18 harness adds paired server assertions: SET DEFAULT preserves old values/file node, WHERE FALSE affects zero rows, NOT VALID retains ACCESS EXCLUSIVE and rejects bad new rows, validation rejects bad old rows, repair permits validation, and CHECK still admits NULL. Existing server tests independently cover stored/virtual/default rewrites and two-session timeout/recovery. These are controlled falsification cases, not statistical precision/recall measurements or claims that all false positives/negatives are eliminated.

Run `moon test --target wasm --deny-warn` (also wasm-gc/js/native), and `moon run --deny-warn checks/postgres.mbtx` against the isolated PostgreSQL 18 database described in `coverage.md`. `--check-only` does not run the server assertions. CI results are the execution evidence.
