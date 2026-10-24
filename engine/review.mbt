///|
fn finding(
  output : Array[Finding],
  part : Segment,
  number : Int32,
  code : String,
  severity : Severity,
  message : String,
  action : String,
) -> Unit {
  output.push({
    code,
    severity,
    statement: number,
    location: part.location,
    message,
    action,
  })
}

///|
/// Review PostgreSQL 18 index migrations on their successful execution path.
/// Unknown statements are retained and invalidate subsequent transaction knowledge.
pub fn review_sql(
  source : String,
  transaction~ : Transaction,
  delivery~ : Delivery,
) -> Review {
  let statements : Array[Statement] = []
  let findings : Array[Finding] = []
  if source.length() > 262144 {
    findings.push({
      code: "PG000",
      severity: Error,
      statement: 0,
      location: location_at(source, 0, source.length()),
      message: "SQL exceeds the 262144 UTF-16 code-unit review limit.",
      action: "Review smaller, independently submitted migrations.",
    })
    return { source, transaction, delivery, statements, findings, }
  }
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
  let mut state = transaction
  if parts.length() > 512 {
    findings.push({
      code: "PG000",
      severity: Error,
      statement: 0,
      location: location_at(source, 0, source.length()),
      message: "SQL exceeds the 512 executable statement review limit.",
      action: "Split the migration into independently reviewed submissions.",
    })
    return { source, transaction, delivery, statements, findings, }
  }
  let mut opened_here = false
  for part in parts {
    let number = statements.length() + 1
    let mut coverage = Unsupported
    let mut operation = "unassessed"
    match transaction_step(part.tokens) {
      Some(Start) => {
        coverage = Analyzed
        operation = "begin"
        if state == Active {
          finding(
            findings,
            part,
            number,
            "PG203",
            Warning,
            "BEGIN does not create a nested PostgreSQL transaction.",
            "Confirm ownership of the surrounding transaction; savepoints need an explicitly supported workflow.",
          )
        } else {
          opened_here = state == Autocommit
        }
        state = Active
      }
      Some(Finish(kind, chain)) => {
        coverage = Analyzed
        operation = kind
        if state == Autocommit {
          finding(
            findings,
            part,
            number,
            "PG205",
            Warning,
            "Transaction end has no known explicit BEGIN.",
            "Check the runner's initial transaction state and the intended boundaries.",
          )
        }
        state = if chain { Active } else { Autocommit }
        opened_here = chain
      }
      None =>
        match index_spec(part.tokens) {
          Some(spec) if part.tokens.length() <= 256 =>
            try @sqlglot.parse_one(part.sql, read="postgres") catch {
              _ => {
                coverage = Invalid
                finding(
                  findings,
                  part,
                  number,
                  "PG001",
                  Error,
                  "SQL parser rejected this index statement.",
                  "Correct the SQL before reviewing it again.",
                )
              }
            } noraise {
              ast =>
                if ast.kind == @syntax.Create && ast.text("kind") == "INDEX" {
                  coverage = Analyzed
                  operation = if spec.concurrent {
                    "create_index_concurrently"
                  } else {
                    "create_index"
                  }
                  if spec.concurrent {
                    let implicit_batch = delivery == SimpleQuery &&
                      parts.length() > 1
                    if state == Active || implicit_batch {
                      finding(
                        findings,
                        part,
                        number,
                        "PG201",
                        Error,
                        "CREATE INDEX CONCURRENTLY cannot run in this explicit or multi-statement implicit transaction.",
                        "Submit this index in its own non-transactional query; changing only the SQL is insufficient.",
                      )
                    } else if state == UnknownTransaction ||
                      delivery == UnknownDelivery {
                      finding(
                        findings,
                        part,
                        number,
                        "PG202",
                        Error,
                        "Concurrent-index transaction compatibility cannot be established from the supplied context.",
                        "Supply the actual initial transaction state and query submission mode; unknown is not autocommit.",
                      )
                    }
                    finding(
                      findings,
                      part,
                      number,
                      "PG105",
                      Advisory,
                      "A failed concurrent build may leave an invalid index; no database state has been inspected.",
                      "Check pg_index.indisvalid after failure and plan database-specific cleanup/retry before deployment.",
                    )
                  } else {
                    finding(
                      findings,
                      part,
                      number,
                      "PG101",
                      Warning,
                      "Ordinary CREATE INDEX prevents concurrent writes while the index is built.",
                      "Assess the write window; consider CONCURRENTLY with a compatible runner and appropriate lock timeout.",
                    )
                  }
                  if spec.unique {
                    finding(
                      findings,
                      part,
                      number,
                      "PG103",
                      Advisory,
                      "Existing data must satisfy the unique index; this review has not checked the database.",
                      "Check duplicate keys using the same index semantics before deployment.",
                    )
                  }
                  if spec.exists {
                    finding(
                      findings,
                      part,
                      number,
                      "PG104",
                      Advisory,
                      "IF NOT EXISTS does not verify the existing index definition or validity.",
                      "Inspect the existing index definition and pg_index.indisvalid.",
                    )
                  }
                }
            }
          _ => ()
        }
    }
    if coverage == Unsupported {
      finding(
        findings,
        part,
        number,
        "PG002",
        Error,
        "Statement is outside the named plain-column index/transaction profile.",
        "Retain this SQL for manual review; unsupported input cannot receive a complete verdict.",
      )
    }
    if coverage != Analyzed {
      state = UnknownTransaction
      opened_here = false
    }
    statements.push({
      number,
      location: part.location,
      sql: part.sql,
      coverage,
      operation,
    })
  }
  if opened_here && state == Active && !parts.is_empty() {
    finding(
      findings,
      parts[parts.length() - 1],
      statements.length(),
      "PG204",
      Warning,
      "The migration opens a transaction still active on its successful completion path.",
      "Close the transaction deliberately or document the runner's responsibility for finishing it.",
    )
  }
  { source, transaction, delivery, statements, findings, }
}
