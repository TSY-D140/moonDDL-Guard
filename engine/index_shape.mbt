///|
priv struct IndexFeatures {
  expression : Bool
  partial : Bool
  covering : Bool
}

///|
fn has_only_keys(expr : @syntax.Expr, allowed : Array[String]) -> Bool {
  expr
  .arg_keys()
  .iter()
  .all(key => {
    match expr.get(key) {
      None => true
      Some(@syntax.List(items)) if items.is_empty() => true
      _ => allowed.contains(key)
    }
  })
}

///|
// Explicit scalar subset: parsing an unfamiliar SQLGlot node never implies
// that the PostgreSQL index profile has assessed it.
fn scalar_supported(expr : @syntax.Expr) -> Bool {
  for node in expr.walk() {
    match node.kind {
      @syntax.Column
      | @syntax.Identifier
      | @syntax.Literal
      | @syntax.Boolean
      | @syntax.Null
      | @syntax.Paren
      | @syntax.Ordered
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
      | @syntax.Is => ()
      _ => return false
    }
    if !has_only_keys(node, [
        "this", "expression", "is_string", "quoted", "desc", "nulls_first", "negate",
        "safe", "typed",
      ]) {
      return false
    }
  }
  true
}

///|
fn index_features(ast : @syntax.Expr) -> IndexFeatures? {
  if ast.kind != @syntax.Create ||
    ast.text("kind") != "INDEX" ||
    !has_only_keys(ast, [
      "this", "kind", "replace", "refresh", "unique", "exists", "concurrently",
    ]) {
    return None
  }
  let index = match ast.this() {
    Some(node) => node
    None => return None
  }
  if index.kind != @syntax.Index ||
    !has_only_keys(index, ["this", "table", "params"]) {
    return None
  }
  let params = match index.arg("params") {
    Some(node) => node
    None => return None
  }
  if !has_only_keys(params, [
      "using", "columns", "include", "where", "with_storage",
    ]) {
    return None
  }
  let columns = params.list("columns")
  let payload = params.list("include")
  if !params.list("with_storage").is_empty() {
    return None
  }
  if columns.is_empty() || columns.length() + payload.length() > 32 {
    return None
  }
  let mut expression = false
  for column in columns {
    if column.kind != @syntax.Ordered || !scalar_supported(column) {
      return None
    }
    let value = match column.this() {
      Some(node) => node
      None => return None
    }
    match value.kind {
      @syntax.Column => ()
      @syntax.Paren | @syntax.Lower | @syntax.Upper | @syntax.Abs =>
        expression = true
      _ => return None // PostgreSQL requires parentheses around non-call expressions.
    }
  }
  for column in payload {
    if column.kind != @syntax.Identifier || !scalar_supported(column) {
      return None
    }
  }
  let partial = match params.arg("where") {
    Some(predicate) => {
      if predicate.kind != @syntax.Where || !has_only_keys(predicate, ["this"]) {
        return None
      }
      let value = match predicate.this() {
        Some(node) => node
        None => return None
      }
      if !scalar_supported(value) {
        return None
      }
      true
    }
    None => false
  }
  Some({ expression, partial, covering: !payload.is_empty(), })
}
