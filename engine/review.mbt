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
/// Review supported PostgreSQL 18 migrations on their successful execution path.
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
  let held_tables : Map[String, HeldTableLock] = Map([])
  let savepoints : Array[SavepointFrame] = []
  let implicit_batch = delivery == SimpleQuery && parts.length() > 1
  let lock_budget = new_timeout("lock_timeout", transaction, implicit_batch)
  let statement_budget = new_timeout(
    "statement_timeout", transaction, implicit_batch,
  )
  for part in parts {
    if state == Autocommit && delivery == PerStatement {
      held_tables.clear()
    }
    let number = statements.length() + 1
    let mut coverage = Unsupported
    let mut operation = "unassessed"
    lock_budget.before(implicit_batch)
    statement_budget.before(implicit_batch)
    if savepoint_step(part.tokens) is Some(step) {
      match
        apply_savepoint(
          step, savepoints, state, lock_budget, statement_budget, held_tables,
        ) {
        Some(name) => {
          coverage = Analyzed
          operation = name
        }
        None =>
          finding(
            findings,
            part,
            number,
            "PG208",
            Error,
            "Savepoint scope cannot be established, its name is unknown, or the 64-point limit was exceeded.",
            "Use a known explicit transaction and a savepoint created within the assessed input; implicit transaction blocks do not support savepoints.",
          )
      }
    } else if timeout_setting(part.tokens) is Some(setting) {
      let tracker = if setting.parameter == "lock_timeout" {
        lock_budget
      } else {
        statement_budget
      }
      if tracker.assign(
          setting, state, delivery, implicit_batch, findings, part, number,
        ) {
        coverage = Analyzed
        operation = (if setting.scoped { "set_local_" } else { "set_" }) +
          setting.parameter
      }
    } else if create_table_spec(part) is Some(spec) {
      coverage = Analyzed
      operation = review_create_table(spec, held_tables, findings, part, number)
      lock_budget.at_index(findings, part, number, subject="statement")
      statement_budget.at_index(findings, part, number, subject="statement")
      timeout_relationship(
        lock_budget, statement_budget, findings, part, number,
      )
    } else if seed_insert_spec(part) is Some(spec) {
      coverage = Analyzed
      operation = review_seed_insert(
        spec, state, implicit_batch, held_tables, findings, part, number,
      )
      lock_budget.at_index(findings, part, number, subject="statement")
      statement_budget.at_index(findings, part, number, subject="statement")
      timeout_relationship(
        lock_budget, statement_budget, findings, part, number,
      )
    } else if data_migration_spec(part) is Some(spec) {
      coverage = if spec.duplicate_assignment { Invalid } else { Analyzed }
      operation = review_data_migration(
        spec, state, implicit_batch, held_tables, findings, part, number,
      )
      lock_budget.at_index(findings, part, number, subject="statement")
      statement_budget.at_index(findings, part, number, subject="statement")
      timeout_relationship(
        lock_budget, statement_budget, findings, part, number,
      )
    } else if rename_spec(part.tokens) is Some(spec) {
      coverage = Analyzed
      operation = review_rename(spec, held_tables, findings, part, number)
      lock_budget.at_index(findings, part, number, subject="statement")
      statement_budget.at_index(findings, part, number, subject="statement")
      timeout_relationship(
        lock_budget, statement_budget, findings, part, number,
      )
    } else if constraint_spec(part) is Some(spec) {
      coverage = Analyzed
      operation = review_constraint(spec, held_tables, findings, part, number)
      lock_budget.at_index(findings, part, number, subject="statement")
      statement_budget.at_index(findings, part, number, subject="statement")
      timeout_relationship(
        lock_budget, statement_budget, findings, part, number,
      )
    } else if removal_tables(part.tokens) is Some(spec) {
      coverage = Analyzed
      operation = review_removal(spec, held_tables, findings, part, number)
      lock_budget.at_index(findings, part, number, subject="statement")
      statement_budget.at_index(findings, part, number, subject="statement")
      timeout_relationship(
        lock_budget, statement_budget, findings, part, number,
      )
    } else if drop_index_spec(part.tokens) is Some(spec) {
      coverage = Analyzed
      operation = if spec.concurrent {
        "drop_index_concurrently"
      } else {
        "drop_index"
      }
      lock_budget.at_index(findings, part, number)
      statement_budget.at_index(findings, part, number)
      timeout_relationship(
        lock_budget, statement_budget, findings, part, number,
      )
      review_drop_index(
        spec, state, delivery, implicit_batch, findings, part, number,
      )
    } else {
      match transaction_step(part.tokens) {
        Some(Start) => {
          lock_budget.begin(state, delivery)
          statement_budget.begin(state, delivery)
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
          savepoints.clear()
          held_tables.clear()
          lock_budget.finish(kind == "rollback", chain, state, delivery)
          statement_budget.finish(kind == "rollback", chain, state, delivery)
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
                  if index_features(ast) is Some(features) {
                    coverage = Analyzed
                    lock_budget.at_index(findings, part, number)
                    statement_budget.at_index(findings, part, number)
                    timeout_relationship(
                      lock_budget, statement_budget, findings, part, number,
                    )
                    operation = if spec.concurrent {
                      "create_index_concurrently"
                    } else {
                      "create_index"
                    }
                    if spec.concurrent {
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
                    if features.expression {
                      finding(
                        findings,
                        part,
                        number,
                        "PG106",
                        Advisory,
                        "Index expressions require immutable functions/operators; their catalog properties were not checked.",
                        "Verify function resolution, immutability and expression-based duplicate keys in the target database.",
                      )
                    }
                    if features.partial {
                      finding(
                        findings,
                        part,
                        number,
                        "PG107",
                        Advisory,
                        "This partial index covers only rows satisfying its predicate; uniqueness and query applicability are conditional.",
                        "Verify predicate immutability and use the same predicate when checking duplicate keys; validate query predicate implication separately.",
                      )
                    }
                    if features.covering {
                      finding(
                        findings,
                        part,
                        number,
                        "PG108",
                        Advisory,
                        "INCLUDE columns are payload, not uniqueness keys; their values can increase index tuple size.",
                        "Check payload width and index tuple limits; do not include payload columns in the uniqueness precheck.",
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
    }
    if coverage == Unsupported {
      finding(
        findings,
        part,
        number,
        "PG002",
        Error,
        "Statement or clause is outside the supported PostgreSQL migration review profile.",
        "Retain this SQL for manual review; unsupported input cannot receive a complete verdict.",
      )
    }
    if coverage != Analyzed {
      savepoints.clear()
      held_tables.clear()
      lock_budget.invalidate()
      statement_budget.invalidate()
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
