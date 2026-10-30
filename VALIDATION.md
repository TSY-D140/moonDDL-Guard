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

The [transaction capability CI run](https://github.com/TSY-D140/moonDDL-Guard/actions/runs/40118420700), revision `31787b8cbbf3bde141adafb6cee36e48b72dcdd5`, completed successfully on Windows, macOS and Linux. Wasm, Wasm-GC and JavaScript tests and CLI help were executed on all three. Native tests were executed on Linux and macOS; Windows native was not executed.

## Report replay and real migration workflow

Current local validation uses the pinned stable compiler/core pair above:

- 18 test groups exercise replay across execution contexts, Unicode/CRLF locations, unknown/nested/duplicate report members, altered diagnostics, malformed SQL, bounded inputs, deterministic serialization and recovery after incomplete statements.
- The end-to-end `.mbtx` runner executes the file CLI against both pinned Umami SQL specimens, persists a report, and replays it. It checks the 17-index complete report and the nine-statement mixed migration's incomplete verdict.
- The script uses fenced frontmatter and current `moonbitlang/async@0.22.5`; it is run with `--deny-warn`.
- Formatting, generated-interface consistency and strict four-target checks are included in CI. Consult the repository's [Actions history](https://github.com/TSY-D140/moonDDL-Guard/actions) for results tied to the current revision; a previous green run is not evidence for later changes.
- Database integration and Windows-native runtime remain unverified. The tool has no live database or production-safety claim.

## B-tree expression, partial and covering indexes (0.4.0)

The profile adds independent PG106/PG107/PG108 preconditions without changing the public API. Tests cover allowed scalar shapes, rejection of unparenthesized arithmetic/subqueries/unknown functions/options, 32 key-plus-payload boundaries, nesting limits, transaction conflicts, source retention and replay. The CLI acceptance script also checks `specimens/advanced.sql` while retaining both original Umami outcomes. The pinned compiler/core remains `0.10.17+d971670cd`.

Revision `05d4b1eb65b646042a5a4449c2da751652f4a9bf` passed [CI run 40121577845](https://github.com/TSY-D140/moonDDL-Guard/actions/runs/40121577845) on all three operating systems. Its 23 test groups ran on Wasm, Wasm-GC and JavaScript everywhere, with native tests on Linux/macOS.

## Timeout settings and transaction scope (0.5.0)

Local Windows validation on the same pinned compiler/core:

- 33 test groups executed and passed on Wasm, Wasm-GC and JavaScript. They cover exact units, integer bounds, 64-character limits, octal ambiguity, rejected rounding/overflow, SESSION/LOCAL override, rollback snapshots, chained/nested transactions, implicit Simple Query scopes, inherited/unknown settings, recovery and deterministic report replay.
- The `.mbtx` acceptance runner executes `bounded-lock.sql` and report replay on all three portable CLI targets and requires equal JSON output. It checks PG201 under whole-file delivery, 100ms/2000ms before/after LOCAL rollback, expression-index preconditions and both unchanged Umami results.
- Formatting and generated-interface consistency are checked; the public interface remains unchanged. Strict all-target compilation passes. Native execution on this Windows host and PostgreSQL server integration remain unverified; Linux/macOS native runtime is checked by CI, not inferred from compilation.
- The new specimens and tests are project-owned; PostgreSQL references and license links are recorded in SOURCES.md. The profile deliberately rejects values requiring PostgreSQL rounding instead of approximating their effective timeout.

For this capability's remote runtime evidence, use the Actions run attached to its commit. Earlier green runs above apply only to those exact revisions.

## Index removal (0.6.0)

37 test groups pass locally on Wasm, Wasm-GC and JavaScript with the pinned compiler/core. Coverage includes concurrent removal's transaction restrictions, unknown contexts, option conflicts, qualified/quoted names, name-count limits, timeout propagation and report replay. The replacement file CLI example returns 0 with explicit catalog preconditions. All-target strict compilation, formatting and interface regeneration are checked. Windows-native and PostgreSQL integration limitations remain unchanged.

## CHECK validation staging (0.7.0)

42 test groups passed on Wasm, Wasm-GC and JavaScript, including the new bounded CHECK grammar, malformed/unsupported predicates, schema/quote-sensitive identity, autocommit versus implicit/explicit transactions, rollback/chain release and incomplete-input recovery. The file CLI checks separate phases and whole-file delivery; only the latter emits PG405 for retained strong locks. Prior index and timeout workflows remain covered. Formatting, generated interfaces, strict all-target compilation and CLI acceptance pass on the pinned compiler/core.

## SARIF export (0.8.0)

46 test groups passed on Wasm, Wasm-GC and JavaScript, with strict all-target compilation, formatting and refreshed interfaces. Export tests cover Unicode/CRLF coordinates, URI byte encoding, path rejection, JSON round trips, deterministic results, severity mapping and preservation of incomplete/empty reports. The acceptance script exercises the three portable CLI targets and replay/invalid-option handling. Five generated reports passed the downloaded OASIS 2.1.0 schema locally using jsonschema 4.25.1; CI runs that check on Linux. Actual GitHub code-scanning ingestion is not verified.

## Baseline comparison (0.9.0)

52 test groups pass on Wasm, Wasm-GC and JavaScript with strict all-target compilation and refreshed interfaces. They check occurrence-counted matching, FIFO duplicate resolution, introduced/resolved conservation, exact SQL identity, changed timeout diagnostics, moved Unicode/CRLF positions, copied arrays, deterministic comparison and strict delta replay. Incomplete current analysis remains exit 2; incomplete or context-mismatched baselines are rejected. The acceptance script passed against the real 17-index Umami baseline, a temporary candidate with one appended index and invalid baseline/context/format combinations.

## Savepoint scope (0.10.0)

57 groups pass on Wasm, Wasm-GC and JavaScript, covering prior behavior plus duplicate-name shadowing, release/rollback differences, timeout restoration, strong-lock lifetime, 64-point and 63-byte identifier boundaries, unknown/inherited scopes and error recovery. The file CLI example checks 100ms before rollback and 2000ms afterward. Strict all-target compilation and interface generation pass on the pinned toolchain; Windows-native and PostgreSQL-server integration remain unverified.

## Index-backed constraint attachment (0.11.0)

61 groups cover concurrent-build/cutover separation, UNIQUE versus PRIMARY KEY conditions, ownership/catalog preconditions, quoted identifiers, explicit/implicit transactions and strong-lock release at commit/savepoint rollback. Empty quoted identifiers and unsupported suffixes are rejected without dropping SQL. The attachment CLI specimen retains its 1000ms budget and reports the cutover lock. Formatting, interface regeneration, strict all-target compilation and portable target tests use the pinned compiler/core.

## Column nullability (0.12.0)

66 groups passed on Wasm, Wasm-GC and JavaScript with formatting, interface generation and strict all-target checks. They check SET versus DROP semantics, no fabricated scan-elision proof, timeout budgets, strong-lock lifetime across commit/savepoint rollback, unsupported/malformed input retention, recovery, SARIF and strict baseline/report/delta replay. The nullability CLI specimen passed under per-statement and whole-file delivery. All eight generated reports passed the OASIS schema locally, including all three added workflows. Added fixtures/tests are project-owned; native execution and PostgreSQL integration limitations above still apply.

One local all-target invocation stopped while checking SQLGlot without a source diagnostic. The identical command and subsequent full verification passed; no dependency source files were edited. Remote evidence must be read from the CI run for the pushed revision, rather than inferred from earlier green runs.

## Expanded core migration review (0.13.0, 2026-10-28)

- Pinned compiler/core: `0.10.17+d971670cd`; moon/moonrun `0.1.20261023`. `moon fmt --check`, `moon info` and `moon check --target all --deny-warn` passed. Generated library/CLI interfaces are unchanged.
- **84 test groups executed and passed independently on Wasm, Wasm-GC and JavaScript.** Existing index, transaction, timeout, savepoint, report, SARIF and baseline behavior remains covered. New cases cover foreign-key actions/lists and both lock targets, lock-class precedence and restoration, bounded column type/default/conversion grammar, destructive actions and malformed/conflicting clauses, report/delta round trips and SARIF rule registration.
- Property/boundary tests replay every character prefix of five new migration forms, retaining source and avoiding unchecked access. Tracked relation identifiers accept 63 UTF-8 bytes and reject 64 bytes, including multibyte names, to prevent unmodeled truncation aliases. Unknown expressions/clauses remain incomplete, with recovery of later supported statements after an explicit boundary.
- `checks/examples.mbtx` passed. New workflows produce identical full JSON reports and successful strict replay on all three portable targets. The real, unmodified Umami mixed migration now diagnoses its added VARCHAR column and two removed columns; unsupported UPDATE/RENAME still prevent a complete review. FK grouped submission additionally emits the retained-write-lock diagnostic.
- **Eleven generated SARIF outputs passed the OASIS 2.1.0 schema**, using external jsonschema 4.25.1. The new FK/column/destructive examples are included; no code-scanning upload is claimed.
- `moon run --deny-warn checks/postgres.mbtx --check-only` compiled and ran successfully. This explicitly did **not** execute PostgreSQL SQL. The new isolated PostgreSQL 18 CI job will check real constraint flags/locks, relation rewrites, dependency/index removal and TRUNCATE/savepoint recovery. No server-integration pass is claimed before observing that job.
- Local Docker server is unavailable (`dockerDesktopLinuxEngine` pipe absent); no local PostgreSQL server integration was executed. `moon test --target native --deny-warn` was actually attempted and failed while selecting the Windows C toolchain: this backend requires MSVC Build Tools/C++ tools and a Windows SDK (`cl.exe` or `clang-cl.exe`). No Windows-native runtime success is claimed. Earlier Linux/macOS native CI successes belong to earlier revisions and do not verify this change.
- Remote main was `15aaa7c9290a3e385091f50477adf420a2b112ec` when checked before the new push. Remote CI/author association and hash synchronization for this revision remain pending until an authorized push.

New rule code, tests, semantic harness and illustrative fixtures are project-owned Apache-2.0; upstream Umami fixtures and their MIT notice are unchanged. The reproducibility matrix is in `handbook/coverage.md`, and the concise updated application is in `handbook/registration.md`.

### PostgreSQL CI bootstrap correction

The authorized push of `a55a46f7d568ba7a03a384af9b8e85e1494f1208` synchronized remote main and GitHub associated both author and committer with TSY-D140. [Run 40717449664](https://github.com/TSY-D140/moonDDL-Guard/actions/runs/40717449664) started its PostgreSQL 18.6 service successfully, but the new standalone job lacked `moon update`: its fresh registry could not resolve `moonbitlang/async`, so no SQL checks ran. The job now initializes the registry explicitly, matching the portable job. This fixes CI dependency bootstrap; actual semantic checks still need a successful rerun.

[Run 40718044897](https://github.com/TSY-D140/moonDDL-Guard/actions/runs/40718044897), revision `6ead8c283e05609c80a13822bc11f028745dffe6`, subsequently passed all four jobs: Windows, Ubuntu, macOS and actual PostgreSQL 18.6 semantic checks. Linux/macOS native tests ran successfully. This closes the historical server-verification gap above; Windows-native remains unverified.

## Rename workflows (0.14.0, 2026-10-30)

88 groups passed on Wasm/Wasm-GC/JavaScript. The tests cover table/column/constraint/index syntax, malformed input retention, schema/quote-sensitive name transfer, savepoint rollback/release of renamed lock identities, timeouts, report/delta replay and SARIF. Portable end-to-end examples passed, including the new rename specimen. Generated public interfaces are unchanged. The PostgreSQL script compiles with `--check-only`; its new server case tests name/index propagation, actual retained lock and rollback, with results to be read from the next relevant CI run. An all-target dependency check emitted a non-source failure once; strict serial all-target verification is repeated rather than changing dependency sources.
