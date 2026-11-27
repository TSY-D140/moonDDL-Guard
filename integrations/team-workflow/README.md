# Adopt the SQL preflight in an ordinary repository

This Apache-2.0 order-service example demonstrates the review cycle without a database or Mooncakes account. The migration SQL is illustrative, not an upstream production fixture. The independent MoonBit library consumer is in `../consumer`.

1. Vendor MoonDDL Guard as a Git submodule (or immutable checkout), pin its commit and use the compiler/core versions from its verification workflow. Review tool upgrades deliberately. These commands run from that checkout; replace the example directory with the application's migration directory.
2. Run `moon run engine/cli -- integrations/team-workflow/migrations --directory --order=lexicographic --boundaries=per-file --transaction=autocommit --delivery=statements --json`. Capture stdout as UTF-8 and **preserve the process exit code**. This draft returns 1 for the blocking index. In CI, upload the JSON with `if: always()` so a failed gate remains inspectable. Order must match the actual runner; supply an exact order plan when lexical order differs. The declared per-file commit boundary must also match it.
3. Read findings and actions. The `revised` version uses `CONCURRENTLY`, returning 0 under the declared context while retaining catalog/failure-recovery advisories. Verify the real runner does not wrap this operation in a transaction. It is a replacement draft, not a second migration to run after the ordinary index.
4. Save the accepted revised report outside the scanned SQL directory. On subsequent changes, use the same command with `--baseline=accepted.json`; 0 means no new blocking findings, 1 means new risk, 2 means incomplete/invalid input. Baselines do not certify safety or suppress incomplete input. Regenerate only after human review of changed context/order or removed/renamed paths.
5. Keep the report/delta as CI artifacts, adjust SQL and rerun. Never ignore exit 2 to obtain a passing build. This tool does not apply migrations.

Run the complete, repeatable acceptance workflow from the checkout:

```sh
moon run --deny-warn checks/team-workflow.mbtx
```

It checks all three portable backends through the actual CLI: draft risk → revised SQL → accepted baseline → appended destructive migration → unsupported SQL → recovery. Reports/deltas are retained in `_build/team-workflow`. CI executes this script on Windows, Linux and macOS. Private infrastructure is unnecessary. See the root workflow for artifact upload syntax and `handbook/directories.md` for bounds, unsupported shared transactions and baseline rules.
