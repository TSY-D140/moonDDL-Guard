# Timeout scope preflight

Version 0.5.0 tracks explicit migration settings for `lock_timeout` and `statement_timeout`. It reports the effective value at each supported index statement on the successful execution path. Use the same session for separately submitted statements; a pool that changes sessions between them needs a different analysis context.

Supported grammar:

```sql
SET [SESSION | LOCAL] lock_timeout {= | TO} value;
SET [SESSION | LOCAL] statement_timeout {= | TO} value;
```

Names and keywords are unquoted and case-insensitive. A value is a single decimal number, a single quoted ASCII duration, or the keyword `DEFAULT`. Units are absent (milliseconds), `ms`, `s`, `min`, `h` or `d`, case-sensitive. The range is 0 through 2147483647ms. Zero disables that parameter; `DEFAULT` restores an unknown inherited configuration, not an assumed zero.

The decimal profile accepts at most six fractional digits and 64 characters after surrounding whitespace is removed. Leading-zero multi-digit integers, signed/exponent/hex/octal forms, microseconds and non-ASCII durations remain unassessed. A conversion must require no PostgreSQL rounding: seconds may have millisecond precision, minutes must resolve to whole seconds, hours to whole minutes and days to whole hours. Thus `'0.001s'` is 1ms, but `'0.0001min'` is rejected rather than reported as 6ms. Express the desired budget as integer milliseconds when uncertain. These are deliberate profile limits; rejection does not imply PostgreSQL rejects the same input.

`SET SESSION` (also plain `SET`) survives commit but is undone by rollback. `SET LOCAL` expires at either transaction end, including `AND CHAIN`; a session setting made in that transaction becomes effective after commit. A later plain `SET` replaces the active local override. Nested BEGIN does not create another setting snapshot. An inherited transaction starts with unknown saved settings. Multi-statement Simple Query implicit blocks share the same setting scope; BEGIN converts that implicit block, so rollback can also undo settings preceding BEGIN in the message.

Outside a known transaction, LOCAL has no effect and emits PG302. Unknown context cannot establish its effect. Unassessed SQL invalidates known settings and transaction state. A recognized boundary and a new supported setting can recover useful subsequent analysis, while the report stays incomplete. [Known savepoints](savepoints.md) restore both session and local values on rollback; release preserves them. RESET, function/set_config calls, other settings and runner-injected changes remain outside the profile.

Diagnostics start only once this migration explicitly sets a tracked parameter. Files with no such settings retain their earlier diagnostics. Absence of a timeout finding never proves a budget exists. PG303 reports uncertainty after a tracked setting becomes unknown; it is an advisory and does not independently make otherwise supported syntax incomplete.

| Code | Meaning |
| --- | --- |
| PG301 | Explicitly disabled lock timeout (warning) |
| PG302 | Ineffective LOCAL outside a transaction (warning) |
| PG303 | Effective tracked timeout unknown (advisory) |
| PG304 | Duration/syntax outside the exact profile (error and incomplete) |
| PG305 | Effective positive lock timeout (advisory) |
| PG306 | Positive lock timeout at least as long as statement timeout (warning) |
| PG307 | Effective positive statement timeout (advisory) |
| PG308 | Explicitly disabled statement timeout (advisory) |

`lock_timeout` bounds each lock acquisition wait; `statement_timeout` bounds the statement including build work. They do not predict build duration, guarantee successful deployment, or describe every timeout the server/client may enforce. A statement timeout can abort a concurrent build, leaving the invalid-index recovery precondition in PG105.

## Reproduce without a database

```sh
moon run engine/cli -- specimens/bounded-lock.sql --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/bounded-lock.sql --transaction=autocommit --delivery=simple-query
moon run engine/cli -- specimens/local-timeout.sql --transaction=autocommit --delivery=statements
moon run checks/examples.mbtx
```

The first returns 0 with PG305=1000ms, PG307=30000ms and PG105. Whole-file delivery returns 1 with PG201 because the concurrent index is in a multi-statement implicit transaction. The LOCAL specimen returns 1 for the ordinary index's PG101, reports 100ms inside the transaction and 2000ms after rollback. Both examples are project-owned illustrations, not production migrations. The acceptance script runs the bounded example and report replay on Wasm, Wasm-GC and JavaScript, compares their JSON, and verifies the LOCAL specimen and unchanged Umami specimens.

Semantics follow PostgreSQL 18 [SET](https://www.postgresql.org/docs/18/sql-set.html), [client defaults](https://www.postgresql.org/docs/18/runtime-config-client.html), [parameter conversion](https://www.postgresql.org/docs/18/config-setting.html) and the [GUC conversion implementation](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/utils/misc/guc.c). No PostgreSQL source or test code is copied.
