///|
priv struct BackfillSource {
  relations : Array[String]
  literal_rows : Int32?
}

///|
fn backfill_scalar(node : @syntax.Expr) -> Bool {
  if node.kind == @syntax.Alias {
    return has_only_keys(node, ["this", "alias"]) &&
      node.arg("alias").bind(ast_identifier) is Some(_) &&
      node.this().map(backfill_scalar).unwrap_or(false)
  }
  // SQLGlot normalizes the built-in gen_random_uuid() to an argument-free Uuid.
  // Do not widen the existing seed/update scalar profiles.
  if node.kind == @syntax.Uuid {
    return has_only_keys(node, [])
  }
  dml_scalar(node)
}

///|
fn backfill_select(query : @syntax.Expr, width : Int32) -> BackfillSource? {
  if width == 0 ||
    query.kind != @syntax.Select ||
    !has_only_keys(query, ["expressions", "from_", "where"]) {
    return None
  }
  let projected = query.list("expressions")
  if projected.length() != width || !projected.iter().all(backfill_scalar) {
    return None
  }
  let from = match query.arg("from_") {
    Some(f) => f
    None => return None
  }
  if from.kind != @syntax.From || !has_only_keys(from, ["this"]) {
    return None
  }
  let source = match from.this() {
    Some(s) => s
    None => return None
  }
  let relations : Array[String] = []
  let literal_rows = if source.kind == @syntax.Values {
    if !has_only_keys(source, ["expressions", "alias"]) {
      return None
    }
    let binding = match source.arg("alias") {
      Some(a) => a
      None => return None
    }
    if binding.kind != @syntax.TableAlias ||
      !has_only_keys(binding, ["this", "columns"]) ||
      binding.this().bind(ast_identifier) is None {
      return None
    }
    let columns = binding.list("columns")
    if columns.is_empty() || columns.length() > 32 {
      return None
    }
    let names : Map[String, Bool] = Map([])
    for column in columns {
      let name = match ast_identifier(column) {
        Some(n) => n
        None => return None
      }
      if names.contains(name) {
        return None
      }
      names[name] = true
    }
    let rows = source.list("expressions")
    if rows.is_empty() || rows.length() > 100 {
      return None
    }
    for row in rows {
      let cells = row.list("expressions")
      if row.kind != @syntax.Tuple ||
        !has_only_keys(row, ["expressions"]) ||
        cells.length() != columns.length() {
        return None
      }
      // Derived VALUES is a literal seed source, never a hidden correlated query.
      for cell in cells {
        if !dml_scalar(cell) ||
          cell
          .walk()
          .any(n => {
            n.kind == @syntax.Column ||
            n.kind == @syntax.CurrentTimestamp ||
            n.kind == @syntax.CurrentDate
          }) {
          return None
        }
      }
    }
    Some(rows.length())
  } else {
    if !has_only_keys(source, ["this", "db", "alias"]) ||
      !dml_relations(source, relations) {
      return None
    }
    None
  }
  if query.arg("where") is Some(predicate) {
    if predicate.kind != @syntax.Where ||
      !has_only_keys(predicate, ["this"]) ||
      !predicate.this().map(n => dml_scalar(n)).unwrap_or(false) {
      return None
    }
  }
  Some({ relations, literal_rows, })
}

///|
fn review_backfill(
  source : BackfillSource,
  held : Map[String, HeldTableLock],
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> Unit {
  finding(
    output,
    part,
    number,
    "PG823",
    Warning,
    if source.literal_rows is Some(n) {
      "INSERT SELECT projects from " +
      n.to_string() +
      " literal source rows; filters/conflicts may reduce the inserted count, while triggers/defaults can add effects."
    } else {
      "INSERT SELECT reads a table snapshot and can insert many rows; WHERE is not a cardinality bound and source changes can affect retries."
    },
    "Measure source plan/cardinality, WAL/replication and transaction budgets. Verify target defaults, triggers, RLS, privileges and type/column compatibility; no data or catalog was inspected.",
  )
  finding(
    output,
    part,
    number,
    "PG824",
    Warning,
    "Backfill retries can duplicate rows or conflict with existing/concurrent writes; random UUID projection is not an idempotency key.",
    "Choose a stable business-key checkpoint and retry contract. Verify unique/FK arbiters; DO NOTHING can skip intended values and DO UPDATE can lock/fail on duplicate keys.",
  )
  if source.relations.any(key => held.contains(key)) {
    finding(
      output,
      part,
      number,
      "PG825",
      Warning,
      "Earlier assessed DDL may retain a stronger lock on the SELECT source during this backfill.",
      "Separate committed metadata and data phases; source reads normally take ACCESS SHARE but inherited stronger locks persist.",
    )
  }
}
