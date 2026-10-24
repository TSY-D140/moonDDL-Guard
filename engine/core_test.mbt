///|
test "ordinary indexes report writes and preserve source" {
  let sql = "CREATE INDEX idx ON public.orders (customer_id, created_at);"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  assert_eq(r.exit_code(), 1)
  assert_eq(r.findings()[0].code, "PG101")
  assert_eq(r.statements()[0].sql, sql)
}

///|
test "unsupported and malformed SQL never look complete" {
  for
    sql in [
      "SELECT 1;", "BOGUS SOMETHING;", "CREATE INDEX x ON t (a) WHERE a > 0;", "CREATE INDEX x ON t (a",
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete())
    assert_eq(r.exit_code(), 2)
  }
}

///|
test "comments quoted semicolons unicode and recovery" {
  let sql = "-- 😀;\r\nCREATE INDEX \"a;b\" ON \"t;x\" (\"c;y\"); /* ; */ SELECT 1; CREATE INDEX z ON t (a);"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(r.statements().length(), 3)
  assert_eq(r.statements()[0].location.line, 2)
  assert_eq(r.statements()[0].location.column, 1)
  assert_eq(r.statements()[0].location.start, 8)
  assert_eq(r.statements()[2].coverage, @moonddl_guard.Analyzed)
  assert_false(r.is_complete())
  let again = @moonddl_guard.review_sql(
    "CREATE INDEX z ON t (a);",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(again.is_complete())
}

///|
test "determinism advisory uniqueness and no mutable array exposure" {
  let sql = "CREATE UNIQUE INDEX IF NOT EXISTS idx ON t (a);"
  let first = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  let second = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(first.to_json().stringify(), second.to_json().stringify())
  assert_eq(first.findings().length(), 3)
  first.findings().clear()
  assert_eq(first.findings().length(), 3)
}

///|
test "empty and lexical failure" {
  let empty = @moonddl_guard.review_sql(
    " ; /* ; */ -- hi",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(empty.statements().length(), 0)
  assert_true(empty.is_complete())
  let bad = @moonddl_guard.review_sql(
    "CREATE INDEX x ON t (\"a",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_false(bad.is_complete())
  assert_eq(bad.findings()[0].code, "PG000")
}
