# Expression, partial and covering indexes

The preflight now assesses these shapes together with execution context. It does not evaluate expressions or prove that a live database can build an index.

- PG106: scalar expressions require immutable functions/operators. Catalog resolution, argument types and collations are unverified. For expression-based unique indexes, check duplicates using the expression rather than its source columns.
- PG107: a partial index covers only rows satisfying its predicate. Unique checks must use that predicate. Query applicability depends on predicate implication; no implication solver or optimizer simulation is provided. Predicate functions must also be immutable.
- PG108: INCLUDE columns store payload and do not participate in uniqueness. Check tuple widths and the actual database's index limits separately.

`specimens/advanced.sql` contains a case-insensitive, partial, covering unique index followed by a full-name expression index. Run the documented file CLI: the concurrent index still needs known autocommit and separate submission, and the ordinary expression index still receives PG101. Input SQL remains verbatim in the report, and report replay preserves all findings.

The profile is deliberately bounded: B-tree only; lower/upper/abs and elementary scalar nodes only. Schema-qualified table names are supported, while qualified expression columns, arbitrary functions, custom opclasses, casts and storage parameters are not. PostgreSQL's extra expression parentheses are required; an unparenthesized `a+b` key is not accepted simply because SQLGlot parses it.

The parser retains default/absent AST argument slots. Empty slots are ignored; any populated argument outside the supported set causes incomplete assessment. Storage parameters and unfamiliar expression nodes are never silently dropped. Public APIs remain unchanged; this is a rule-profile expansion in 0.4.0. Historical reports must be replayed using their producing release if their findings differ.

References: https://www.postgresql.org/docs/18/indexes-expressional.html , https://www.postgresql.org/docs/18/indexes-partial.html , https://www.postgresql.org/docs/18/sql-createindex.html .
