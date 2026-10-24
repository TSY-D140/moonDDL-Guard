///|
/// Review the PostgreSQL 18 profile. Unknown syntax is retained and blocks CI.
/// This first profile accepts non-concurrent, named, plain-column indexes.
pub fn review_sql(
  source : String,
  transaction~ : Transaction,
  delivery~ : Delivery,
) -> Review {
  let statements : Array[Statement] = []
  let findings : Array[Finding] = []
  let parts = segments(source) catch {
    _ => {
      findings.push({
        code: "PG000",
        severity: Error,
        statement: 0,
        location: location_at(source, 0, source.length()),
        message: "SQL tokenization failed; no statements were evaluated.",
        action: "Check unterminated quotes/comments and unsupported lexical syntax.",
      })
      return { source, transaction, delivery, statements, findings, }
    }
  }
  for part in parts {
    let number = statements.length() + 1
    let mut coverage = Unsupported
    let mut operation = "unassessed"
    try @sqlglot.parse_one(part.sql, read="postgres") catch {
      _ => {
        coverage = Invalid
        findings.push({
          code: "PG001",
          severity: Error,
          statement: number,
          location: part.location,
          message: "SQL parser rejected this statement.",
          action: "Correct the SQL before reviewing it again.",
        })
      }
    } noraise {
      ast =>
        match index_spec(part.tokens) {
          Some(spec) if ast.kind == @syntax.Create &&
            ast.text("kind") == "INDEX" &&
            !spec.concurrent => {
            coverage = Analyzed
            operation = "create_index"
            findings.push({
              code: "PG101",
              severity: Warning,
              statement: number,
              location: part.location,
              message: "Ordinary CREATE INDEX prevents concurrent writes while the index is built.",
              action: "Assess the write window; consider CONCURRENTLY with a compatible runner and appropriate lock timeout.",
            })
            if spec.unique {
              findings.push({
                code: "PG103",
                severity: Advisory,
                statement: number,
                location: part.location,
                message: "Existing data must satisfy the unique index; this review has not checked the database.",
                action: "Check duplicate keys using the same index semantics before deployment.",
              })
            }
            if spec.exists {
              findings.push({
                code: "PG104",
                severity: Advisory,
                statement: number,
                location: part.location,
                message: "IF NOT EXISTS does not verify the existing index definition or validity.",
                action: "Inspect the existing index definition and pg_index.indisvalid.",
              })
            }
          }
          _ =>
            findings.push({
              code: "PG002",
              severity: Error,
              statement: number,
              location: part.location,
              message: "Statement is outside the current plain-column index profile.",
              action: "Retain this SQL for manual review; unsupported input cannot receive a complete verdict.",
            })
        }
    }
    statements.push({
      number,
      location: part.location,
      sql: part.sql,
      coverage,
      operation,
    })
  }
  { source, transaction, delivery, statements, findings, }
}
