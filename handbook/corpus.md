# Real migrations before syntax expansion

The added corpus contains 24 unmodified migrations from Umami, Supabase Storage and Cal.com, eight per project. Together with the existing two Umami files, the repository now has 26 real migration specimens from three projects. [Manifest and sampling method](../specimens/corpus/README.md) pin commit, path, license and original Git blob for every added file. No SQL is filtered out to improve coverage.

## Observed baseline, current 0.21.0 rules

Counts below use the declared autocommit/per-statement comparison context. Unknown-context runs have the same coverage counts but can have different execution warnings. Neither context establishes the upstream runner's actual behavior. Counts describe this sample, not all migrations in these projects or general PostgreSQL compatibility.

| Project | Files | Completely assessed files | Analyzed statements | Unsupported statements | Invalid statements |
| --- | ---: | ---: | ---: | ---: | ---: |
| Umami | 8 | 3 | 65 | 7 | 0 |
| Supabase Storage | 8 | 1 | 1 | 25 | 0 |
| Cal.com | 8 | 5 | 18 | 4 | 0 |
| Total | 24 | 9 | 84 | 36 | 0 |

15 files remain incomplete and return exit 2; those are expected regression outcomes, not approved migrations. The zero-invalid count does not certify syntax validity: unsupported statements have not undergone full PostgreSQL validation. Procedural bodies count as their containing statement; nested SQL is not assessed independently.

## What the unsupported statements actually contain

This inventory groups the 36 top-level unsupported statements by their dominant visible form. It is a manual triage of source files/full reports, not automatic proof of a parser's precise rejection point. Counts are mutually exclusive here; different clauses inside one statement can need separate engineering work.

| Observed form | Statements / files / projects | Evidence and decision |
| --- | --- | --- |
| Multiple ADD COLUMN actions in one ALTER TABLE | 6 / 4 / 2 | [Umami 1](../specimens/corpus/umami/1.sql), [2](../specimens/corpus/umami/2.sql), [5](../specimens/corpus/umami/5.sql), [Cal.com 6](../specimens/corpus/calcom/6.sql): next bounded capability |
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

**Prioritize a bounded multi-ADD-COLUMN ALTER workflow next; do not expand grammar in this corpus change.** The repeated pattern appears in two independent applications and four sampled files. If fully supported, those four files are candidates to become complete (9 to 13 of 24); this is an opportunity estimate, not an implemented coverage claim.

The next implementation should initially accept only supported ordinary ADD COLUMN actions on one table. Preserve the original statement and source positions; reject the entire statement when any action is unknown, malformed or beyond the bound. Do not split and execute SQL or certify a supported prefix. Review the strongest lock and combined scan/rewrite/default/nullability effects once in the actual statement/transaction context, including savepoint recovery and later retained-lock warnings. Add property tests for commas inside typemods/expressions/quoted literals, malformed trailing actions, action limits, replay/baselines and unknown-input recovery. Execute representative combined ADDs against PostgreSQL 18 before claiming server semantics.

General combined ALTER, procedural/routine review, privilege changes and enum-array rewrites remain separate proposals. Add a second independent real-project workflow before promoting a single-project family solely on frequency. No public API or supported grammar changed in this corpus milestone.

## Reproduce and review a regression

```sh
moon run --deny-warn checks/corpus.mbtx
moon run --deny-warn checks/corpus-summary.mbtx
```

The first command validates fixture/license bytes, original source spans, both execution contexts, strict replay and portable equivalent output, then compares ordered operations and diagnostic code/severity/statement/location tuples with the checked-in baseline. A mismatch fails verification; it does not auto-update expectations. The second prints per-file counts and bounded unsupported SQL previews. Full SQL and diagnostics stay in `_build/corpus/*-CONTEXT.json`; previews are not transformed migration inputs. CI retains that directory as an artifact on every OS, including failures where available. Normal checks need no live upstream repository or database.

These added migrations are analyzed but **not executed**. Existing PostgreSQL integration evidence remains limited to its documented semantic cases and the earlier matching-schema Umami fixture; it must not be generalized to these three upstream deployments.
