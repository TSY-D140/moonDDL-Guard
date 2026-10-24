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
