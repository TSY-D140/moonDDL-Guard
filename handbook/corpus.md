# Real migrations before syntax expansion

The added corpus contains 24 unmodified migrations from Umami, Supabase Storage and Cal.com, eight per project. Together with the existing two Umami files, the repository now has 26 real migration specimens from three projects. [Manifest and sampling method](../specimens/corpus/README.md) pin commit, path, license and original Git blob for every added file. No SQL is filtered out to improve coverage.

## Original observed baseline, 0.21.0 rules

Counts below use the declared autocommit/per-statement comparison context. Unknown-context runs have the same coverage counts but can have different execution warnings. Neither context establishes the upstream runner's actual behavior. Counts describe this sample, not all migrations in these projects or general PostgreSQL compatibility.

| Project | Files | Completely assessed files | Analyzed statements | Unsupported statements | Invalid statements |
| --- | ---: | ---: | ---: | ---: | ---: |
| Umami | 8 | 3 | 65 | 7 | 0 |
| Supabase Storage | 8 | 1 | 1 | 25 | 0 |
| Cal.com | 8 | 5 | 18 | 4 | 0 |
| Total | 24 | 9 | 84 | 36 | 0 |

At that baseline, 15 files were incomplete and returned exit 2. Expected regression outcomes are not approved migrations. The zero-invalid count does not certify syntax validity: unsupported statements have not undergone full PostgreSQL validation. Procedural bodies count as their containing statement; nested SQL is not assessed independently.

## Current 0.22.0 result after bounded multi-ADD support

| Project | Files | Completely assessed files | Analyzed statements | Unsupported statements |
| --- | ---: | ---: | ---: | ---: |
| Umami | 8 | 6 | 70 | 2 |
| Supabase Storage | 8 | 1 | 1 | 25 |
| Cal.com | 8 | 6 | 19 | 3 |
| Total | 24 | 13 | 90 | 30 |

The four expected files now become complete; eleven files remain incomplete. Six statements change from unsupported to `add_columns`. Only the eight corresponding case/context baseline observations changed; the other forty are identical, including diagnostics and locations. Original SQL, licenses and hashes are unchanged. This measures the selected sample, not general compatibility.

## What the original unsupported statements contained

This inventory groups the 36 top-level unsupported statements by their dominant visible form. It is a manual triage of source files/full reports, not automatic proof of a parser's precise rejection point. Counts are mutually exclusive here; different clauses inside one statement can need separate engineering work.

| Observed form | Statements / files / projects | Evidence and decision |
| --- | --- | --- |
| Multiple ADD COLUMN actions in one ALTER TABLE | 6 / 4 / 2 | [Umami 1](../specimens/corpus/umami/1.sql), [2](../specimens/corpus/umami/2.sql), [5](../specimens/corpus/umami/5.sql), [Cal.com 6](../specimens/corpus/calcom/6.sql): implemented in 0.22.0; other listed forms remain unsupported |
| CREATE OR REPLACE FUNCTION | 9 / 4 / 1 | Storage 2/3/5/7: routine replacement, SECURITY DEFINER, search_path and body semantics need a coherent separate design |
| DO blocks | 8 / 2 / 1 | Storage 4/7: dynamic SQL, role discovery, conditional DDL, retry loops and locking; keep opaque/incomplete |
| REVOKE | 4 / 1 / 1 | Storage 7: privilege and routine identity rules needed; do not treat as generic harmless DDL |
| CREATE TABLE with additional lexical/definition forms | 2 / 2 / 2 | Cal.com 0 has E-string defaults; Storage 7 has an unquoted `key` column. Record the whole definition; isolate exact rejection causes before widening identifiers/literals |
| SELECT | 2 / 2 / 1 | Storage 0 is `select 1`; Storage 7 invokes a state-changing routine. A SELECT-shaped statement is not generally side-effect free |
| INSERT SELECT | 1 / 1 / 1 | Umami 4: real backfill from existing rows; future work must model source cardinality, expressions and write risks |
| Array expression UPDATE / array type conversion | 2 / 1 / 1 | Cal.com 7: enum-array replacement is one composed workflow; enabling an array token alone would be insufficient |
| Collated partial concurrent index | 1 / 1 / 1 | Storage 6: collation/operator and predicate contracts needed; ordinary-index support does not cover it |
| CREATE EXTENSION | 1 / 1 / 1 | Umami 0: extension scripts and privileges are not certified from the extension name |

The Storage sample demonstrates why raw unsupported-statement counts should not decide the roadmap: most function/DO/permission work comes from one service, and many statements cluster in one migration.

## Syntax decision

**The selected bounded multi-ADD-COLUMN workflow is implemented in 0.22.0.** The repeated pattern appeared in two independent applications and four sampled files. Those four files now become complete, improving the observed result from 9 to 13 of 24. See the [supported boundary and runnable workflow](combined-additions.md).

The implementation accepts two to 32 supported ordinary ADD COLUMN actions on one table. It preserves the original statement and source positions and rejects the entire statement when any action is unknown, malformed or beyond the bound. PG501 covers the shared lock once; PG521 explains combined rewrite/validation costs, while per-column findings retain their original action locations. Property tests cover commas, bounds, malformed suffixes, replay/baselines and savepoint/unknown-input recovery. The PostgreSQL harness includes exact upstream migrations and representative shared-lock/default/rollback cases; actual server success must be read from the corresponding CI run.

General combined ALTER, procedural/routine review, privilege changes and enum-array rewrites remain separate proposals. Add a second independent real-project workflow before promoting a single-project family solely on frequency. Public function signatures remain unchanged; `Statement.operation` adds `add_columns` and older affected reports require regeneration for strict replay.

## Reproduce and review a regression

```sh
moon run --deny-warn checks/corpus.mbtx
moon run --deny-warn checks/corpus-summary.mbtx
```

The first command validates fixture/license bytes, original source spans, both execution contexts, strict replay and portable equivalent output, then compares ordered operations and diagnostic code/severity/statement/location tuples with the checked-in baseline. A mismatch fails verification; it does not auto-update expectations. The second prints per-file counts and bounded unsupported SQL previews. Full SQL and diagnostics stay in `_build/corpus/*-CONTEXT.json`; previews are not transformed migration inputs. CI retains that directory as an artifact on every OS, including failures where available. Normal checks need no live upstream repository or database.

The corpus harness itself never executes SQL. The PostgreSQL harness now includes Umami 1/2/5 and Cal.com 6 on minimal matching disposable tables. Verify its actual outcome in [VALIDATION.md](../VALIDATION.md) and the corresponding CI before claiming server execution success; none of this verifies the three complete upstream deployments.
