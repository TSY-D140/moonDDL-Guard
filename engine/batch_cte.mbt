///|
// Exactly one read-only SELECT CTE. Write CTEs, recursion and general queries
// are rejected: parsing a LIMIT never proves a bound on the outer DML.
fn bounded_batch_cte(
  clause : @syntax.Expr,
  relations : Array[String],
) -> String? {
  if clause.kind != @syntax.With ||
    !has_only_keys(clause, ["expressions", "recursive"]) ||
    clause.bool_arg("recursive") {
    return None
  }
  let ctes = clause.list("expressions")
  if ctes.length() != 1 {
    return None
  }
  let cte = ctes[0]
  if cte.kind != @syntax.CTE || !has_only_keys(cte, ["this", "alias"]) {
    return None
  }
  let binding = match cte.arg("alias") {
    Some(a) => a
    None => return None
  }
  if binding.kind != @syntax.TableAlias || !has_only_keys(binding, ["this"]) {
    return None
  }
  let name = match binding.this() {
    Some(n) =>
      match ast_identifier(n) {
        Some(s) => s
        None => return None
      }
    None => return None
  }
  let query = match cte.this() {
    Some(q) => q
    None => return None
  }
  if query.kind != @syntax.Select ||
    !has_only_keys(query, [
      "expressions", "from_", "where", "order", "limit", "locks",
    ]) {
    return None
  }
  let selected = query.list("expressions")
  if selected.is_empty() ||
    selected.length() > 32 ||
    !selected.iter().all(n => dml_scalar(n, returning=true)) {
    return None
  }
  let from = match query.arg("from_") {
    Some(f) => f
    None => return None
  }
  if from.kind != @syntax.From ||
    !has_only_keys(from, ["this"]) ||
    !from.this().map(n => dml_relations(n, relations)).unwrap_or(false) {
    return None
  }
  if query.arg("where") is Some(predicate) {
    if predicate.kind != @syntax.Where ||
      !has_only_keys(predicate, ["this"]) ||
      !predicate.this().map(n => dml_scalar(n)).unwrap_or(false) {
      return None
    }
  }
  if query.arg("order") is Some(order) {
    if order.kind != @syntax.Order || !has_only_keys(order, ["expressions"]) {
      return None
    }
    let columns = order.list("expressions")
    if columns.is_empty() || columns.length() > 32 {
      return None
    }
    for column in columns {
      if column.kind != @syntax.Ordered ||
        !has_only_keys(column, ["this", "desc", "nulls_first"]) ||
        !column.this().map(n => dml_scalar(n)).unwrap_or(false) {
        return None
      }
    }
  }
  let limit = match query.arg("limit") {
    Some(l) => l
    None => return None
  }
  if limit.kind != @syntax.Limit || !has_only_keys(limit, ["expression"]) {
    return None
  }
  let value = match limit.expression() {
    Some(v) => v
    None => return None
  }
  if value.kind != @syntax.Literal || value.is_string() {
    return None
  }
  let text = value.text("this")
  if text.is_empty() || text.length() > 6 {
    return None
  }
  let mut count = 0
  for ch in text {
    let code = ch.to_int()
    if code < 48 || code > 57 {
      return None
    }
    count = count * 10 + code - 48
  }
  if count > 100000 {
    return None
  }
  for lock in query.list("locks") {
    if lock.kind != @syntax.Lock ||
      !has_only_keys(lock, ["update", "key", "wait"]) {
      return None
    }
    match lock.get("wait") {
      None | Some(@syntax.Bool(_)) => ()
      _ => return None
    }
  }
  Some(name)
}
