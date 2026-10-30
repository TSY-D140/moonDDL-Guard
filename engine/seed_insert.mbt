///|
priv struct SeedInsertSpec {
  table : String
  conflict : Bool
  updating : Bool
  returning_rows : Bool
}

///|
fn seed_column(node : @syntax.Expr) -> String? {
  if node.kind != @syntax.Column || !has_only_keys(node, ["this"]) {
    return None
  }
  node.this().bind(ast_identifier)
}

///|
fn seed_returning(ast : @syntax.Expr) -> Bool? {
  match ast.arg("returning") {
    None => Some(false)
    Some(clause) => {
      let items = clause.list("expressions")
      if clause.kind != @syntax.Returning ||
        !has_only_keys(clause, ["expressions", "into"]) ||
        clause.bool_arg("into") ||
        items.is_empty() ||
        items.length() > 32 ||
        !items.iter().all(n => dml_scalar(n, returning=true)) {
        return None
      }
      Some(true)
    }
  }
}

///|
fn seed_insert_spec(part : Segment) -> SeedInsertSpec? {
  if !word(part.tokens, 0, "INSERT") || part.tokens.length() > 1024 {
    return None
  }
  let mut depth = 0
  for token in part.tokens {
    if token.token_type == @syntax.L_PAREN {
      depth += 1
    }
    if token.token_type == @syntax.R_PAREN {
      depth -= 1
    }
    if depth < 0 || depth > 32 {
      return None
    }
  }
  if depth != 0 {
    return None
  }
  let ast = @sqlglot.parse_one(part.sql, read="postgres") catch {
    _ => return None
  }
  let flags = [
    "is_function", "stored", "by_name", "exists", "partition", "settings", "overwrite",
    "ignore", "source",
  ]
  let allowed = ["this", "expression", "default", "conflict", "returning"]
  allowed.append(flags)
  if ast.kind != @syntax.Insert ||
    !has_only_keys(ast, allowed) ||
    flags.iter().any(key => ast.bool_arg(key)) {
    return None
  }
  let target = match ast.this() {
    Some(t) => t
    None => return None
  }
  let mut table = target
  let mut column_count = 0
  if target.kind == @syntax.Schema {
    if !has_only_keys(target, ["this", "expressions"]) {
      return None
    }
    let columns = target.list("expressions")
    if columns.is_empty() || columns.length() > 32 {
      return None
    }
    let names : Map[String, Bool] = Map([])
    for node in columns {
      let name = match ast_identifier(node) {
        Some(n) => n
        None => return None
      }
      if names.contains(name) {
        return None
      }
      names[name] = true
    }
    column_count = columns.length()
    table = match target.this() {
      Some(t) => t
      None => return None
    }
  }
  let relations : Array[String] = []
  if !has_only_keys(table, ["this", "db"]) ||
    !dml_relations(table, relations) ||
    relations.length() != 1 {
    return None
  }
  if ast.bool_arg("default") {
    if ast.arg("expression") is Some(_) || column_count != 0 {
      return None
    }
  } else {
    let values = match ast.arg("expression") {
      Some(v) => v
      None => return None
    }
    let rows = values.list("expressions")
    if values.kind != @syntax.Values ||
      !has_only_keys(values, ["expressions"]) ||
      rows.is_empty() ||
      rows.length() > 100 {
      return None
    }
    let mut width = column_count
    for row in rows {
      let cells = row.list("expressions")
      if row.kind != @syntax.Tuple ||
        !has_only_keys(row, ["expressions"]) ||
        cells.is_empty() ||
        cells.length() > 32 {
        return None
      }
      if width == 0 {
        width = cells.length()
      }
      if cells.length() != width ||
        !cells.iter().all(n => dml_scalar(n, assignment=true)) {
        return None
      }
    }
  }
  let mut updating = false
  let conflict = match ast.arg("conflict") {
    None => false
    Some(clause) => {
      if clause.kind != @syntax.OnConflict ||
        !has_only_keys(clause, [
          "duplicate", "action", "conflict_keys", "expressions", "where",
        ]) ||
        clause.bool_arg("duplicate") {
        return None
      }
      let action = match clause.arg("action") {
        Some(a) => a
        None => return None
      }
      if action.kind != @syntax.Var || !has_only_keys(action, ["this"]) {
        return None
      }
      updating = action.text("this") == "DO UPDATE"
      if !updating && action.text("this") != "DO NOTHING" {
        return None
      }
      let keys = clause.list("conflict_keys")
      if keys.length() > 32 || (updating && keys.is_empty()) {
        return None
      }
      let names : Map[String, Bool] = Map([])
      for key in keys {
        if key.kind != @syntax.Ordered ||
          !has_only_keys(key, ["this", "nulls_first"]) ||
          key.bool_arg("nulls_first") {
          return None
        }
        let name = match key.this().bind(seed_column) {
          Some(n) => n
          None => return None
        }
        if names.contains(name) {
          return None
        }
        names[name] = true
      }
      let assignments = clause.list("expressions")
      if !updating &&
        (!assignments.is_empty() || clause.arg("where") is Some(_)) {
        return None
      }
      if updating {
        if assignments.is_empty() || assignments.length() > 32 {
          return None
        }
        let assigned : Map[String, Bool] = Map([])
        for item in assignments {
          if item.kind != @syntax.EQ ||
            !has_only_keys(item, ["this", "expression"]) {
            return None
          }
          let name = match item.this().bind(seed_column) {
            Some(n) => n
            None => return None
          }
          if assigned.contains(name) {
            return None
          }
          assigned[name] = true
          if !item
            .expression()
            .map(n => dml_scalar(n, assignment=true))
            .unwrap_or(false) {
            return None
          }
        }
        if clause.arg("where") is Some(predicate) {
          if predicate.kind != @syntax.Where ||
            !has_only_keys(predicate, ["this"]) ||
            !predicate.this().map(n => dml_scalar(n)).unwrap_or(false) {
            return None
          }
        }
      }
      true
    }
  }
  let returning_rows = match seed_returning(ast) {
    Some(value) => value
    None => return None
  }
  Some({ table: relations[0], conflict, updating, returning_rows, })
}

///|
fn review_seed_insert(
  spec : SeedInsertSpec,
  state : Transaction,
  implicit_batch : Bool,
  held : Map[String, HeldTableLock],
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  finding(
    output,
    part,
    number,
    "PG821",
    Warning,
    "INSERT seed rows can wait on unique/FK/row locks and fail on defaults, identity, generated columns, types, triggers or RLS; VALUES bounds do not prove database effects.",
    "Verify the actual schema, privileges, conflict keys and defaults; bound transaction/WAL budgets and test retries on representative data. No database rows are inspected.",
  )
  if held.contains(spec.table) {
    finding(
      output,
      part,
      number,
      "PG803",
      Warning,
      "An earlier assessed DDL may retain a stronger lock on the INSERT target during seeding.",
      "Commit the blocking metadata phase before data seeding; separately budget data transactions.",
    )
  }
  if spec.conflict {
    finding(
      output,
      part,
      number,
      "PG822",
      Warning,
      if spec.updating {
        "ON CONFLICT DO UPDATE locks conflicting rows; duplicate input keys can attempt to affect the same row twice and fail."
      } else {
        "ON CONFLICT DO NOTHING can silently leave existing row values unchanged; it does not verify seed data matches the requested values."
      },
      "Verify eligible immediate unique/exclusion arbiters, input key uniqueness and intended retry semantics. A DO UPDATE WHERE filter still locks conflicts even if it skips their updates.",
    )
  }
  if state != Autocommit || implicit_batch {
    finding(
      output,
      part,
      number,
      "PG804",
      Warning,
      "Seed writes run in an active/implicit transaction or an initially unknown transaction scope.",
      "Keep data batches independently committed and budget lock duration; sequence values consumed by failed inserts/conflicts need not roll back.",
    )
  }
  if spec.returning_rows {
    finding(
      output,
      part,
      number,
      "PG807",
      Advisory,
      "INSERT RETURNING exposes inserted/updated row data; skipped conflicts need not return a row.",
      "Handle empty results and sensitive columns deliberately; consume output without assuming one result per input row.",
    )
  }
  if spec.updating {
    "upsert_seed_rows"
  } else {
    "insert_seed_rows"
  }
}
