///|
test "index replacement and concurrent cleanup are usable end to end" {
  let sql = "SET lock_timeout='1s'; CREATE INDEX CONCURRENTLY new_idx ON t(a); DROP INDEX CONCURRENTLY IF EXISTS public.old_idx RESTRICT;"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  assert_eq(r.exit_code(), 0)
  assert_eq(r.statements()[2].operation, "drop_index_concurrently")
  assert_eq(r.findings().filter(f => f.code == "PG305").length(), 2)
  assert_eq(
    r.to_json(),
    @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
  )
  assert_eq(
    r.statements()[2].sql,
    "DROP INDEX CONCURRENTLY IF EXISTS public.old_idx RESTRICT;",
  )
}

///|
test "concurrent drops require known nontransactional submission" {
  for
    (transaction, delivery, code) in [
      (@moonddl_guard.Active, @moonddl_guard.PerStatement, "PG206"),
      (@moonddl_guard.Autocommit, @moonddl_guard.SimpleQuery, "PG206"),
      (@moonddl_guard.UnknownTransaction, @moonddl_guard.PerStatement, "PG207"),
      (@moonddl_guard.Autocommit, @moonddl_guard.UnknownDelivery, "PG207"),
    ] {
    let r = @moonddl_guard.review_sql(
      "DROP INDEX CONCURRENTLY x; DROP INDEX CONCURRENTLY y;",
      transaction~,
      delivery~,
    )
    assert_eq(r.findings().filter(f => f.code == code).length(), 2)
    assert_eq(r.is_complete(), code != "PG207")
  }
  let r = @moonddl_guard.review_sql(
    "BEGIN; DROP INDEX CONCURRENTLY x; ROLLBACK; DROP INDEX CONCURRENTLY y;",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(r.findings().filter(f => f.code == "PG206").length(), 1)
}

///|
test "drop lock cascade and concurrent option conflicts stay visible" {
  for
    sql in [
      "DROP INDEX x, public.y CASCADE;", "DROP INDEX CONCURRENTLY x,y;", "DROP INDEX CONCURRENTLY x CASCADE;",
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete())
    assert_eq(r.exit_code(), 1)
    assert_eq(r.findings().filter(f => f.code == "PG110").length(), 1)
  }
  let r = @moonddl_guard.review_sql(
    "DROP INDEX x,y CASCADE;",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(r.findings().map(f => f.code), ["PG109", "PG112", "PG110"])
}

///|
test "drop grammar preserves quoted names and refuses unknown suffixes" {
  for
    sql in [
      "DROP INDEX", "DROP INDEX x,", "DROP INDEX IF x", "DROP INDEX a.b.c", "DROP INDEX x ON t",
      "DROP INDEX (x)", "DROP INDEX x RESTRICT CASCADE",
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete(), msg=sql)
  }
  let r = @moonddl_guard.review_sql(
    "DROP INDEX CONCURRENTLY \"s;x\".\"i;y\";",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  let names = StringBuilder()
  for i in 0..<32 {
    if i > 0 {
      names.write_string(",")
    }
    names.write_string("i\{i}")
  }
  let sql = "DROP INDEX " + names.to_string()
  assert_true(
    @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
  assert_false(
    @moonddl_guard.review_sql(
      sql + ",extra",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
}
