# Ordered migration-directory review

Version 0.24.0 adds a library workflow and directory CLI. Every file has its own path-associated review with local source positions. SQL is read unchanged; files are never concatenated, rewritten or executed. Existing single-file CLI/report behavior remains available.

## Run the real two-file example

From the repository root:

```sh
moon run engine/cli -- specimens/upstream --directory --order=specimens/upstream/order.json --boundaries=per-file --transaction=autocommit --delivery=statements --json
```

Returns exit 1 with a `moonddl.batch.v1` report for the two complete, licensed Umami files. The plan orders the selected index migration before the selected mixed migration. They are a subset of upstream history; this is not a complete deployable chain or a statement about the upstream runner's context. The command explicitly supplies the context for this static comparison.

An order plan is exact JSON:

```json
{"format":"moonddl.order.v1","files":["001-init/migration.sql","002-add/migration.sql"]}
```

Alternatively, explicitly choose `--order=lexicographic`. This uses lexical path order, not natural numeric order or inferred chronology. No default file order is assumed. Discovery recursively includes all files whose names end in `.sql` case-insensitively, including hidden directories; other file types are outside SQL inventory. An explicit plan must exactly match the inventory. Missing, stale, duplicate or case-colliding paths fail with exit 2, so a newly added migration cannot be silently omitted. There are no implicit vendor/git exclusions: pass a migration directory rather than a repository root.

## Execution contract and limits

`--boundaries=per-file` is mandatory and declares that each file's transaction/lock scope ends before the next file. `--transaction` and `--delivery` describe the initial context within **each** file, including `active` for a separately committed runner wrapper. SQL text alone does not establish runner behavior. Cross-file open transactions are unsupported and must not use this mode. Inherited session settings are conservatively unknown at every file start; they are neither propagated nor assumed reset. Settings established inside a file are assessed normally. This workflow does not simulate cross-file catalog changes, data state or migration execution/history.

Limits: 1–256 SQL files, 1 Mi UTF-16 code units of aggregate SQL, 16 directory levels, 4096 visited directory entries and 32 MiB per read artifact/file. Batch/delta serialized replay is bounded to 8 Mi UTF-16 code units; the larger byte-read budget allows UTF-8 encodings of those Unicode artifacts. Limits cause explicit rejection, not truncation or partial success. Paths use `/`, are relative and exclude empty/dot/parent segments, drives, schemes and controls. Validation is lexical; the portable filesystem adapter follows filesystem aliases rather than resolving/confining symlinks. Use a trusted checkout; alias cycles eventually fail at the depth bound. It does not claim sandbox confinement or physical-file uniqueness.

Any unsupported SQL keeps its file and the batch incomplete (exit 2), while later files are still reviewed. I/O, invalid UTF-8, inventory, order or configuration errors reject the operation with a path-aware diagnostic; `--json` returns the existing `moonddl.error.v1` envelope. SARIF export of a whole directory and cross-file transactions are not implemented; neither is silently approximated.

## Save, replay and gate

Save JSON stdout as UTF-8, then replay it without order/context overrides:

```sh
moon run engine/cli -- saved-batch.json --directory --replay --json
moon run engine/cli -- specimens/upstream --directory --order=specimens/upstream/order.json --boundaries=per-file --transaction=autocommit --delivery=statements --baseline=saved-batch.json --json
```

The second returns 0 for the same complete batch, although known risks remain visible in the full per-file reports. New appended files are gated using their full review; edits to existing files use occurrence-aware `compare_reviews`. Removed, renamed or reordered baseline paths, or insertion before the old order prefix, reject comparison until inventory changes are explicitly reviewed and a baseline regenerated. An incomplete baseline or mismatched initial execution context is rejected. Current incompleteness always takes precedence over baseline suppression. Baselines are review artifacts, not records that migrations have been applied.

`moonddl.batch.v1` retains boundaries, initial context, ordered paths and complete reports. `moonddl.batch-delta.v1` retains both batches plus per-path existing/added comparisons. Strict decoders reject duplicate members, unknown/missing fields, altered derived verdicts, mixed contexts and invalid paths. These are recomputation checks, not signatures or authenticated filesystem snapshots. CLI replay accepts batch reports; delta replay is exposed through the library.

## Library and verification

Use `review_isolated_files(Array[MigrationInput], transaction~, delivery~)`, `decode_batch`, `compare_batches`, `decode_batch_delta` and `decode_file_order`. `BatchReview::files()` returns copied path/report entries, and report/delta types expose `to_json`, `to_text` and `exit_code`; batches also expose `is_complete`. The primary API includes a tested documentation example; the independent consumer exercises review/replay/gating without the CLI.

```sh
moon run --deny-warn checks/directory.mbtx
moon run --deny-warn checks/consumer.mbtx
```

The end-to-end script copies the existing unmodified Umami inputs to `_build`, tests a deliberately nonlexical manifest on Wasm/Wasm-GC/JavaScript, then checks exact replay, unchanged and appended-file gates, unlisted-file rejection, invalid options/UTF-8 and incomplete-file retention/recovery. No SQL is executed. Linux/macOS CI additionally runs this same script with `-- --native`; Windows-native remains unverified. Seven core regression groups cover the new integrity/order/path/size/baseline and state-boundary properties. All new code/tests/plan/docs are project-owned Apache-2.0; fixture provenance and MIT notices remain in `specimens/upstream` and `SOURCES.md`.
