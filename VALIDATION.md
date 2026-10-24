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
