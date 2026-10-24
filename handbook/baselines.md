# Gate newly introduced findings

Use `compare_reviews(baseline, current)` to compare two reviews from the same execution context. A baseline must be complete; a current review may be incomplete, but its delta always returns 2. The comparison returns new and resolved findings plus an unchanged finding count. Returned arrays are copies.

Identity includes exact statement SQL, diagnostic code, severity, message and next action. Statement numbers/locations may move. Repeated identities are matched in occurrence order, so an extra copy remains introduced instead of being hidden by a set. Whitespace or spelling changes inside a statement conservatively create new identities; there is no SQL normalization or semantic-equivalence claim. Changes to preceding timeout/transaction conditions can change diagnostic identities too.

Delta exit 0 means no introduced warning/error and complete current analysis. Exit 1 means an introduced warning/error; new advisories remain visible. Existing warnings remain in the full current review but no longer fail this explicit baseline gate. This is not deployment approval, and resolved means only “absent from this review,” not a database repair. An incomplete or context-mismatched baseline is rejected rather than used to suppress findings.

```sh
moon run engine/cli -- specimens/upstream/indexes.sql --transaction=autocommit --delivery=statements --json > baseline.json
moon run engine/cli -- specimens/upstream/indexes.sql --transaction=autocommit --delivery=statements --baseline=baseline.json --json
moon run checks/examples.mbtx
```

The first returns 1 for 17 known PG101 warnings; the second returns 0 with 17 unchanged findings. The acceptance script then appends one project-owned CREATE INDEX to a temporary copy and verifies exit 1 with one introduced warning and no resolved findings. The upstream specimen is never modified. --replay may supply a persisted current review; its recorded context is compared with the baseline's. --sarif cannot be combined with --baseline; SARIF always exports the full review.

`ReviewDelta::to_json` retains both entire input reports and all derived fields in moonddl.delta.v1. `decode_delta` replays both reports and recomputes the comparison, rejecting unknown/duplicate/missing fields and edited results. JSON parsing/serialization is deterministic and bounded to 16777216 UTF-16 code units; each embedded review still obeys its own limits. This has no signature or authentication. Historical baselines must be regenerated when they no longer replay under the current rules. The CLI consumes baseline/current review reports, not serialized delta input; downstream MoonBit programs can use decode_delta.
