# Execution context

`transaction` describes the state immediately before the first submitted SQL, not a runner brand or a guessed default. `delivery=statements` means each statement is sent and completed separately, with its own protocol synchronization. It does not describe an extended-protocol pipeline without intervening Sync. `delivery=simple-query` means this entire file is one PostgreSQL Simple Query message. Other submission schemes must use `unknown`.

A Simple Query message with multiple executable statements runs in an implicit transaction, except where explicit transaction controls change its boundaries. New implicit blocks after COMMIT still belong to the same multi-statement message, so concurrent indexes are rejected there too. Empty delimiters and comments do not count as executable statements.

Supported controls: BEGIN [WORK|TRANSACTION], START TRANSACTION, COMMIT/END and ROLLBACK/ABORT with optional WORK/TRANSACTION and AND [NO] CHAIN. BEGIN inside an active transaction does not nest it. A transaction opened by this migration and not closed is reported; an inherited active transaction is not automatically called dangling. Savepoints, prepared transactions and isolation options are unassessed rather than guessed.

This models the successful execution path. It does not assume SQL after a database error was executed. An unknown statement may change transaction state, so subsequent context becomes unknown until an explicit recognized boundary restores it. The whole review remains incomplete even after that recovery.

## Diagnostics

| Code | Meaning |
| --- | --- |
| PG000 | Tokenization failed or input exceeded the review limit |
| PG001 | Supported-looking index rejected by the parser |
| PG002 | Statement or clause outside the supported profile |
| PG101 | Ordinary index build prevents concurrent writes |
| PG103 | Unique-index data precondition not checked |
| PG104 | Existing index definition/validity not established |
| PG105 | Concurrent-build failure recovery must be planned |
| PG201 | Concurrent index incompatible with known transaction context |
| PG202 | Concurrent-index compatibility cannot be established |
| PG203 | Nested BEGIN does not start a nested transaction |
| PG204 | Transaction opened here remains active on success path |
| PG205 | Transaction end has no known explicit BEGIN |

PG202 makes the review incomplete. Other known transaction conflicts can be completely analyzed yet still return exit 1. Advisory findings remain visible at exit 0; no live data or production-safety proof is produced.
