///|
priv struct DataMigrationSpec {
  deleting : Bool
  filtered : Bool
  all_rows : Bool
  joined : Bool
  returning_rows : Bool
  duplicate_assignment : Bool
  batch_cte : Bool
  relations : Array[String]
}

///|
fn ast_identifier(node : @syntax.Expr) -> String? {
  if node.kind != @syntax.Identifier || !has_only_keys(node, ["this", "quoted"]) {
    return None
  }
  let name = node.text("this")
  if name.is_empty() || @utf8.encode(name).length() > 63 {
    return None
  }
  let result = StringBuilder()
  for i in 0..<name.length() {
    let c = name.code_unit_at(i)
    let unit = name[i:i + 1].to_owned()
    result.write_string(
      if !node.bool_arg("quoted") && c >= 65 && c <= 90 {
        unit.to_lower()
      } else {
        unit
      },
    )
  }
  Some(result.to_string())
}

///|
fn dml_type(node : @syntax.Expr) -> Bool {
  if !has_only_keys(node, ["this", "expressions", "nested"]) ||
    node.bool_arg("nested") {
    return false
  }
  let name = match node.datatype_this() {
    Some(dtype) => dtype.name()
    None => return false
  }
  if ![
      "INT", "BIGINT", "SMALLINT", "TEXT", "BOOLEAN", "DATE", "TIMESTAMP", "TIMESTAMPTZ",
      "TIME", "TIMETZ", "UUID", "VARCHAR", "CHAR", "DECIMAL", "DOUBLE", "JSON", "JSONB",
    ].contains(name) {
    return false
  }
  let text = StringBuilder()
  text.write_string(if name == "DOUBLE" { "DOUBLE PRECISION" } else { name })
  let params = node.list("expressions")
  if !params.is_empty() {
    text.write_string("(")
    for i, param in params {
      if param.kind != @syntax.DataTypeParam || !has_only_keys(param, ["this"]) {
        return false
      }
      let value = match param.this() {
        Some(v) => v
        None => return false
      }
      if value.kind != @syntax.Literal || value.is_string() {
        return false
      }
      if i > 0 {
        text.write_string(",")
      }
      text.write_string(value.text("this"))
    }
    text.write_string(")")
  }
  let tokens = @sqlglot.dialect("postgres").tokenize(text.to_string()) catch {
    _ => return false
  }
  column_type(tokens, 0).map(pair => pair.0 == tokens.length()).unwrap_or(false)
}

///|
fn dml_scalar(
  expr : @syntax.Expr,
  returning~ : Bool = false,
  assignment~ : Bool = false,
) -> Bool {
  if assignment && expr.kind == @syntax.Var && expr.text("this") == "DEFAULT" {
    return has_only_keys(expr, ["this"])
  }
  if assignment &&
    expr.kind == @syntax.Column &&
    expr.name() == "DEFAULT" &&
    expr.this().map(n => !n.bool_arg("quoted")).unwrap_or(false) {
    return has_only_keys(expr, ["this"])
  }
  for node in expr.walk() {
    let allowed = match node.kind {
      @syntax.Identifier => {
        if ast_identifier(node) is None ||
          (!node.bool_arg("quoted") && node.text("this") == "DEFAULT") {
          return false
        }
        ["this", "quoted"]
      }
      @syntax.Column => ["this", "table", "db"]
      @syntax.Coalesce => ["this", "expressions"]
      @syntax.In => {
        if node.list("expressions").is_empty() ||
          node.list("expressions").length() > 64 {
          return false
        }
        ["this", "expressions"]
      }
      @syntax.Between => ["this", "low", "high"]
      @syntax.Cast => ["this", "to"]
      @syntax.DataType => {
        if !dml_type(node) {
          return false
        }
        ["this", "expressions", "nested"]
      }
      @syntax.DataTypeParam => ["this"]
      @syntax.CurrentTimestamp | @syntax.CurrentDate => []
      @syntax.Star if returning => []
      @syntax.Alias if returning => ["this", "alias"]
      @syntax.Literal
      | @syntax.Boolean
      | @syntax.Null
      | @syntax.Paren
      | @syntax.Lower
      | @syntax.Upper
      | @syntax.Abs
      | @syntax.Add
      | @syntax.Sub
      | @syntax.Mul
      | @syntax.Div
      | @syntax.Mod
      | @syntax.DPipe
      | @syntax.Neg
      | @syntax.EQ
      | @syntax.NEQ
      | @syntax.GT
      | @syntax.GTE
      | @syntax.LT
      | @syntax.LTE
      | @syntax.And
      | @syntax.Or
      | @syntax.Not
      | @syntax.Is
      | @syntax.Like
      | @syntax.ILike =>
        ["this", "expression", "is_string", "safe", "typed", "negate"]
      _ => return false
    }
    if !has_only_keys(node, allowed) {
      return false
    }
  }
  true
}

///|
fn dml_relations(
  table : @syntax.Expr,
  relations : Array[String],
  virtual_tables~ : Array[String] = [],
) -> Bool {
  if table.kind != @syntax.Table ||
    !has_only_keys(table, ["this", "db", "alias", "only", "joins"]) {
    return false
  }
  let name = match table.this() {
    Some(n) =>
      match ast_identifier(n) {
        Some(s) => s
        None => return false
      }
    None => return false
  }
  let names : Array[String] = []
  if table.arg("db") is Some(schema) {
    match ast_identifier(schema) {
      Some(s) => names.push(s)
      None => return false
    }
  }
  names.push(name)
  if names.length() != 1 || !virtual_tables.contains(name) {
    relations.push(Json(names).stringify())
  }
  if relations.length() > 32 {
    return false
  }
  if table.arg("alias") is Some(binding) {
    if binding.kind != @syntax.TableAlias || !has_only_keys(binding, ["this"]) {
      return false
    }
    if binding.this().map(n => ast_identifier(n) is Some(_)).unwrap_or(false) ==
      false {
      return false
    }
  }
  for join in table.list("joins") {
    if join.kind != @syntax.Join ||
      !has_only_keys(join, ["this", "on", "using", "side", "kind"]) {
      return false
    }
    if !["", "LEFT", "RIGHT", "FULL"].contains(join.text("side")) ||
      !["", "INNER", "OUTER", "CROSS"].contains(join.text("kind")) {
      return false
    }
    if join.arg("on") is Some(condition) {
      if !dml_scalar(condition) {
        return false
      }
    }
    for column in join.list("using") {
      if ast_identifier(column) is None {
        return false
      }
    }
    if join
      .this()
      .map(n => dml_relations(n, relations, virtual_tables~))
      .unwrap_or(false) ==
      false {
      return false
    }
  }
  true
}

///|
fn data_migration_spec(part : Segment) -> DataMigrationSpec? {
  if part.tokens.length() > 512 ||
    (
      !word(part.tokens, 0, "UPDATE") &&
      !word(part.tokens, 0, "DELETE") &&
      !word(part.tokens, 0, "WITH")
    ) {
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
  let deleting = ast.kind == @syntax.Delete
  if (!deleting && ast.kind != @syntax.Update) ||
    !has_only_keys(
      ast,
      if deleting {
        ["this", "using", "where", "returning", "cluster", "with_"]
      } else {
        ["this", "expressions", "from_", "where", "returning", "with_"]
      },
    ) ||
    ast.bool_arg("cluster") {
    return None
  }
  let relations : Array[String] = []
  let target = match ast.this() {
    Some(t) => t
    None => return None
  }
  if !target.list("joins").is_empty() || !dml_relations(target, relations) {
    return None
  }
  let virtual_tables : Array[String] = []
  let batch_cte = match ast.arg("with_") {
    None => false
    Some(clause) => {
      let binding = match bounded_batch_cte(clause, relations) {
        Some(name) => name
        None => return None
      }
      virtual_tables.push(binding)
      true
    }
  }
  let mut duplicate_assignment = false
  if !deleting {
    let assigned : Map[String, Bool] = Map([])
    let assignments = ast.list("expressions")
    if assignments.is_empty() || assignments.length() > 32 {
      return None
    }
    for item in assignments {
      if item.kind != @syntax.EQ || !has_only_keys(item, ["this", "expression"]) {
        return None
      }
      let column = match item.this() {
        Some(c) => c
        None => return None
      }
      if column.kind != @syntax.Column || !has_only_keys(column, ["this"]) {
        return None
      }
      let name = match column.this() {
        Some(n) =>
          match ast_identifier(n) {
            Some(s) => s
            None => return None
          }
        None => return None
      }
      if assigned.contains(name) {
        duplicate_assignment = true
      }
      assigned[name] = true
      if item
        .expression()
        .map(n => dml_scalar(n, assignment=true))
        .unwrap_or(false) ==
        false {
        return None
      }
    }
  }
  if ast.arg("from_") is Some(from) {
    if from.kind != @syntax.From || !has_only_keys(from, ["this"]) {
      return None
    }
    if from
      .this()
      .map(n => dml_relations(n, relations, virtual_tables~))
      .unwrap_or(false) ==
      false {
      return None
    }
  }
  for source in ast.list("using") {
    if !dml_relations(source, relations, virtual_tables~) {
      return None
    }
  }
  let joined = relations.length() > 1
  let mut all_rows = false
  let filtered = match ast.arg("where") {
    Some(predicate) => {
      if predicate.kind != @syntax.Where || !has_only_keys(predicate, ["this"]) {
        return None
      }
      let value = match predicate.this() {
        Some(v) => v
        None => return None
      }
      if !dml_scalar(value) {
        return None
      }
      all_rows = value.kind == @syntax.Boolean && value.bool_arg("this")
      true
    }
    None => false
  }
  let returning_rows = match ast.arg("returning") {
    Some(returning) => {
      if returning.kind != @syntax.Returning ||
        !has_only_keys(returning, ["expressions", "into"]) ||
        returning.bool_arg("into") {
        return None
      }
      let values = returning.list("expressions")
      if values.is_empty() ||
        values.length() > 32 ||
        !values.iter().all(v => dml_scalar(v, returning=true)) {
        return None
      }
      true
    }
    None => false
  }
  Some({
    deleting,
    filtered,
    all_rows,
    joined,
    returning_rows,
    duplicate_assignment,
    batch_cte,
    relations,
  })
}

///|
fn review_data_migration(
  spec : DataMigrationSpec,
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
    "PG801",
    Warning,
    "UPDATE/DELETE acquires ROW EXCLUSIVE and affected-row locks; large changes can cause contention, WAL/replica lag and dead tuples.",
    "Measure the actual plan and row count on representative data; use bounded, resumable batches and an intentional transaction/timeout budget. WHERE alone is not a row-count bound.",
  )
  if !spec.filtered || spec.all_rows {
    finding(
      output,
      part,
      number,
      "PG802",
      Error,
      "This data migration has no WHERE restriction or uses literal WHERE TRUE; all eligible target rows may be changed or removed.",
      "Verify the full affected set, backups and intended predicate before execution. Joins, RLS and triggers are catalog/runtime conditions, not a safety proof.",
    )
  }
  if spec.relations.iter().any(key => held.contains(key)) {
    finding(
      output,
      part,
      number,
      "PG803",
      Warning,
      "An earlier assessed DDL may retain a stronger access/write-blocking lock on a participating relation during this data migration.",
      "Commit the metadata/constraint phase before backfilling or deleting; rename and savepoint operations preserve the tracked lock identities.",
    )
  }
  if state != Autocommit || implicit_batch {
    finding(
      output,
      part,
      number,
      "PG804",
      Warning,
      "This data migration runs in an active/implicit transaction or its initial transaction duration is unknown.",
      "Keep batches short and independently committed; long transactions retain row locks and old snapshots. SQL after server errors is not simulated.",
    )
  }
  if spec.joined {
    finding(
      output,
      part,
      number,
      "PG805",
      Warning,
      if spec.deleting {
        "DELETE USING can select target rows through multiple source relations; join selectivity and dependencies are unknown."
      } else {
        "UPDATE FROM must match at most one source row per target for predictable assigned values; source uniqueness was not verified."
      },
      "Verify the join keys, source uniqueness and execution plan. A source LIMIT or filtering predicate does not by itself bound target changes.",
    )
  }
  finding(
    output,
    part,
    number,
    "PG806",
    Advisory,
    "Affected-row cardinality, indexes, data types, function resolution, triggers, RLS, foreign-key actions and partition movement were not inspected.",
    "Check those conditions in the target database. DELETE can cascade and UPDATE conversions/constraints can fail; no data backup or rollback script is generated.",
  )
  if spec.returning_rows {
    finding(
      output,
      part,
      number,
      "PG807",
      Advisory,
      "RETURNING can stream many rows or sensitive columns; client memory and downstream consumers are unverified.",
      "Consume returned data deliberately and bound client resource use; RETURNING does not limit affected rows.",
    )
  }
  if spec.duplicate_assignment {
    finding(
      output,
      part,
      number,
      "PG810",
      Error,
      "UPDATE assigns the same canonical column more than once; PostgreSQL rejects duplicate assignments.",
      "Provide one expression per target column; quoted case and ASCII-folded unquoted names are distinguished.",
    )
  }
  if spec.batch_cte {
    finding(
      output,
      part,
      number,
      "PG811",
      Advisory,
      "The SELECT CTE has a literal LIMIT; target-row bounds, progress and join uniqueness remain unverified.",
      "Match on a verified unique target key, commit batches, and make progress resumable. SKIP LOCKED can omit locked rows; repeat/reconcile rather than claiming the backfill is complete.",
    )
  }
  if spec.deleting {
    "delete_rows"
  } else {
    "update_rows"
  }
}
