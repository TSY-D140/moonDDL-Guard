# Validation record

## Foundation

Local host: Windows. Installed compiler: `moonc v0.10.14+7d59c7ec9`; moon/moonrun `0.1.20260920`. The official stable manifest read on 2026-10-24 reports `moonc v0.10.17+d971670cd` and moon `0.1.20261023`. Downloading that distribution is currently blocked by DNS/network failures, so the installed compiler is not described as the latest stable release.

- Wasm: 5 tests executed, passed.
- Wasm-GC: 5 tests executed, passed.
- JavaScript/Node: 5 tests executed, passed.
- File CLI: executed against `specimens/ordinary.sql`; emitted PG101/PG103/PG104 and returned the expected status 1.
- Native execution: attempted, blocked because no system C compiler (`cc`, `gcc`, or `clang`) was found. No native runtime success is claimed.
- PostgreSQL server integration: not run. Docker's server pipe is unavailable locally.
- CI: configuration is present; remote execution is not yet verified.

Source-level checks and generated interfaces are refreshed before each commit. Subsequent capabilities append their actual test results here.

## Transaction-aware preflight

- 11 test groups executed and passed on Wasm, Wasm-GC and JavaScript.
- Concurrent unique-index CLI example executed: status 0 with PG105/PG103 advisories.
- Explicit-transaction example executed: status 1 with PG201 at statement 2; the success-path analysis recovers known transaction state after ROLLBACK.
- Tests distinguish whole-file Simple Query grouping from separately synchronized statements, preserve quoted/dollar-quoted control words as unsupported SQL, and retain incomplete status after unknown statements.
- Native/runtime, PostgreSQL integration and remote CI limitations above still apply.

The network recovered and the current stable distribution was installed in an isolated workspace: moon/moonrun `0.1.20261023`, moonc `v0.10.17+d971670cd`. Sources and interfaces were migrated using its formatter (`Int32`, current JSON conversion), and CI pins this compiler/core pair. The first remote foundation run failed on old-formatter `Int` spelling; it did not reach test execution. That historical failure is retained rather than reported as success.
