///|
test "key nesting and arithmetic boundaries" {
  let keys = StringBuilder()
  for i in 0..<32 {
    if i > 0 {
      keys.write_string(",")
    }
    keys.write_string("c\{i}")
  }
  let sql = "CREATE INDEX x ON t (" + keys.to_string() + ")"
  assert_true(
    @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
  assert_false(
    @moonddl_guard.review_sql(
      sql + " INCLUDE (extra);",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
  let nested = StringBuilder()
  for _ in 0..<33 {
    nested.write_string("(")
  }
  nested.write_string("a")
  for _ in 0..<33 {
    nested.write_string(")")
  }
  assert_false(
    @moonddl_guard.review_sql(
      "CREATE INDEX x ON t (" + nested.to_string() + ");",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
  for expr in ["((a / b))", "((-a * b % 3))", "(upper(email))"] {
    assert_true(
      @moonddl_guard.review_sql(
        "CREATE INDEX x ON t " + expr + ";",
        transaction=@moonddl_guard.Autocommit,
        delivery=@moonddl_guard.PerStatement,
      ).is_complete(),
      msg=expr,
    )
  }
}

///|
test "expression partial and covering indexes retain independent preconditions" {
  let sql = "CREATE UNIQUE INDEX CONCURRENTLY x ON public.users USING btree (lower(email) DESC NULLS LAST) INCLUDE (id) WHERE deleted_at IS NULL;"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  assert_eq(r.exit_code(), 0)
  assert_eq(r.findings().map(f => f.code), [
    "PG105", "PG106", "PG107", "PG108", "PG103",
  ])
  assert_eq(r.statements()[0].sql, sql)
  assert_eq(
    @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    r.to_json(),
  )
}

///|
test "bounded scalar expressions and predicates are supported" {
  for
    body in [
      "(lower(email))", "((a + b))", "((first_name || ' ' || last_name))", "(abs(a)) WHERE a > 0 AND b IS NOT NULL",
      "(a DESC NULLS FIRST) INCLUDE (b, \"c;d\") WHERE NOT (b = 0 OR a < 1)",
    ] {
    let r = @moonddl_guard.review_sql(
      "CREATE INDEX x ON t " + body + ";",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete(), msg=body)
    assert_eq(r.exit_code(), 1)
  }
}

///|
test "unassessed functions options subqueries and invalid suffixes fail closed" {
  for
    tail in [
      "(random())", "(custom_fn(a))", "((SELECT 1))", "(sum(a))", "(a + b)", "(a text_pattern_ops)",
      "(a COLLATE \"C\")", "(a) WITH (fillfactor=70)", "(a) TABLESPACE fast", "(a) NULLS NOT DISTINCT",
      "(a) WHERE a > 0 BOGUS", "(a) INCLUDE ((a + 1))", "(a) WHERE EXISTS (SELECT 1)",
    ] {
    let r = @moonddl_guard.review_sql(
      "CREATE INDEX x ON t " + tail + ";",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete(), msg=tail)
    assert_eq(r.exit_code(), 2)
  }
  let gin = @moonddl_guard.review_sql(
    "CREATE INDEX x ON t USING gin (a);",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_false(gin.is_complete())
}

///|
test "extended indexes still respect transactions and unknown-statement recovery" {
  let sql = "BEGIN; CREATE INDEX CONCURRENTLY x ON t (lower(a)) WHERE b IS NULL; ROLLBACK; CREATE INDEX CONCURRENTLY y ON t (a) INCLUDE (b);"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG201").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG108").length(), 1)
}
