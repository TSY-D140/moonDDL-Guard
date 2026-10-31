# Explain incomplete coverage

PG002 still means the entire statement is unassessed and the review is incomplete (exit 2). It now identifies confirmed constructs or limits when possible, and points to their original source region:

| Recognized construct | Diagnostic focus and next step |
| --- | --- |
| DO | Procedural/dynamic body remains opaque; review the full body and called routines |
| CREATE [OR REPLACE] FUNCTION | Routine identity/body/privileges/search_path require review; location points to FUNCTION |
| GRANT/REVOKE | Check object signatures, roles and effective access |
| INSERT query source | Location points to SELECT; check cardinality, dependencies, retries and write effects |
| COLLATE | Preserve the clause and verify collation/operator/type eligibility |
| Array/subscript syntax | Preserve element types, casts and expressions; scalar support does not cover the workflow |
| Unsupported combined ALTER | Check all actions against the bounded ordinary multi-ADD profile; mixed clauses, duplicate names and unsupported expressions remain incomplete |
| ALTER token/action limits | Point to the first token/separator beyond the 256-token or 32-action profile |

These are explanations of recognized unassessed constructs, not a claim to have found every parser error or proved that the rest of the statement is valid. Unknown cases keep the existing generic message. Supported statements are not reclassified by this pass, and keyword-like strings/quoted names are not treated as active clauses. Commas in bracketed arrays or parenthesized expressions do not count as action separators.

```sh
moon run engine/cli -- specimens/corpus/storage/7.sql --json --transaction=autocommit --delivery=statements
moon run engine/cli -- specimens/corpus/umami/4.sql --json --transaction=autocommit --delivery=statements
```

Both retain the complete original SQL and return 2. Findings identify the relevant line/column; `Statement.sql` and the report's `source` are not shortened to that region. Text, JSON and SARIF share these diagnostics. Do not delete an unsupported construct or split a transaction solely to obtain a complete verdict. Suggested handbook paths are review guidance, not automatically executed fixes.

Strict replay recomputes diagnostics and rejects older affected reports; regenerate them with the current release. Tests cover each family, exact Unicode/CRLF marker ranges, supported-input preservation, quoted keyword text, array commas and recovery at explicit boundaries. Implementation/tests are project-owned Apache-2.0; references are PostgreSQL 18 [ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html), [INSERT](https://www.postgresql.org/docs/18/sql-insert.html) and [CREATE FUNCTION](https://www.postgresql.org/docs/18/sql-createfunction.html), without copied upstream code/tests.
