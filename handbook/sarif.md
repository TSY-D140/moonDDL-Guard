# SARIF for code review

`Review::to_sarif(artifact_path)` exports SARIF 2.1.0. The argument is a repository-relative filesystem path, not a pre-encoded URI. Backslashes become separators; reserved characters and UTF-8 bytes are percent encoded. Absolute paths, schemes/drives, empty/dot segments, control characters, unpaired UTF-16 surrogates and paths longer than 4096 UTF-16 units are rejected with ExportError. No filesystem access occurs in the library.

Results retain every diagnostic, severity and next action. Source locations use UTF-16 columns and character offsets/lengths, explicitly declared by columnKind. The artifact contains the full source. run.properties.moonddlReview retains the complete original report, including unsupported statements and execution context, for deterministic replay. executionSuccessful means analysis is complete; ordinary risk findings still use the normal review exit code 1. Incomplete analysis remains exit 2 and executionSuccessful=false.

```sh
moon run engine/cli -- specimens/ordinary.sql --transaction=autocommit --delivery=statements --sarif > review.sarif
moon run engine/cli -- review.json --replay --sarif --artifact=specimens/ordinary.sql > replay.sarif
```

The first intentionally returns 1. Replay requires the original SQL artifact path explicitly; it never labels the JSON report as SQL. --json and --sarif are mutually exclusive. The API raises on invalid paths; the CLI prints the reason and returns 2.

```sh
python -m pip install jsonschema==4.25.1
moon run checks/sarif-schema.mbtx
```

This optional verification requires curl, Python and network access to download the versioned OASIS schema into _build. It validates five generated reports (warning, transaction error, unsupported SQL, lexical failure, empty SQL). CI runs it on Linux. Portable tests and the acceptance script check SARIF generation on Wasm, Wasm-GC and JavaScript. No schema copy is vendored.

The output is tested against the [OASIS schema](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/schemas/sarif-schema-2.1.0.json). GitHub's [SARIF ingestion requirements](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support) include additional UI limits. No actual GitHub code-scanning upload has been performed, and no custom cross-run fingerprint is emitted. Do not treat schema validation as proof of every consumer's behavior.
