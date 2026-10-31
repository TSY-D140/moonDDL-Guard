# Pinned production migration corpus

24 complete, unmodified SQL files from three independent projects complement the two existing Umami specimens in `../upstream`. These are real upstream migration inputs, not synthetic examples or a claim of upstream adoption.

| Project | Pinned commit | Directory | Fixture license |
| --- | --- | --- | --- |
| [Umami](https://github.com/umami-software/umami) | `559e3c607c23d2c72d9bd4f6481bda428255323c` | `prisma/migrations` | MIT, full notice in `umami/LICENSE` |
| [Supabase Storage](https://github.com/supabase/storage) | `9d15cdc93c0b1afc37708914f5e45f865b231d48` | `migrations/tenant` | Apache-2.0, full license in `storage/LICENSE` |
| [Cal.com](https://github.com/calcom/cal.com) | `a5ee96f77edd644439e7de8c3255ccb2eb2c5941` | `packages/prisma/migrations` | MIT at this commit, full notice in `calcom/LICENSE` |

`manifest.json` contains every upstream path, direct source URL, original Git blob hash, commit, directory population and sampling position. Within each pinned directory, enumerate SQL paths lexicographically and select eight indices `floor(i * (n - 1) / 7)`, `i = 0..7`. Include both ends of the directory's history without filtering by size, features, analysis success or risk. Path order is a sampling proxy, not a claim about commit dates or release chronology.

The sample is deliberately small and not statistically representative: two projects use Prisma and one is PostgreSQL-specific infrastructure. Large initial schemas and procedural migrations can dominate statement totals. Report file and project recurrence alongside statement counts; do not advertise a population-wide coverage percentage. These files are separate inputs, not a deployable migration chain with all dependencies.

From the repository root:

```sh
moon run --deny-warn checks/corpus.mbtx
```

This offline-fixture regression checks original SQL/license blob hashes, source and statement-span preservation, explicit incomplete verdicts, strict report replay in two contexts, and Wasm/Wasm-GC/JavaScript output equivalence in the explicit context. The contexts are unknown runner settings and a declared autocommit/per-statement comparison. The latter is not asserted to match any upstream runner's deployment behavior. Public dependencies and the toolchain must already be available for offline use.

Full per-file reports and the aggregate results go to `_build/corpus/`; CI uploads these as `migration-corpus-OS` artifacts. `expected.json` pins coverage, ordered operations and diagnostic tuples `[code, severity, statement, location]` for both contexts, so severity downgrades and misplaced diagnostics are visible too. An expected incomplete result is a regression success, not evidence that the SQL is safe. To intentionally update behavior, inspect the report changes, then run `moon run --deny-warn checks/corpus.mbtx -- --record` and review the baseline diff. Normal verification never rewrites the baseline.

To reproduce the imported files, run `moon run --deny-warn checks/corpus-fetch.mbtx`. This explicitly downloads the pinned directories/files from public GitHub, verifies original blob hashes and regenerates the manifest; it does not regenerate the analysis baseline. The importer refuses discovered migration-local or parent-directory license overrides for manual review. Source bytes and notices retain their upstream terms; the harness and documentation are project-owned Apache-2.0. `.gitattributes` disables fixture newline conversion on checkout.

These SQL files are never executed by the corpus harness. The separate PostgreSQL 18 integration job executes Umami 1/2/5 and Cal.com 6 on matching disposable tables, alongside existing semantic cases; it does not verify the projects' complete schemas or deployments. Read [observed gaps and the syntax decision](../../handbook/corpus.md) before proposing further parser expansion, and [actual server evidence](../../VALIDATION.md) before claiming a new integration case has passed.
