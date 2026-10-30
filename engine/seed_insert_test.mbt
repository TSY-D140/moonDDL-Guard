///|
test "seed inserts and conflict actions receive workflow diagnostics" {
  for
    (sql, operation) in [
      (
        "INSERT INTO public.orders(id,status) VALUES (1,'new'),(2,'old') ON CONFLICT(id) DO NOTHING RETURNING id",
        "insert_seed_rows",
      ),
      ("INSERT INTO orders DEFAULT VALUES", "insert_seed_rows"),
      (
        "INSERT INTO orders(id,status) VALUES(1,'new') ON CONFLICT(id) DO UPDATE SET status=excluded.status WHERE orders.status IS NULL",
        "upsert_seed_rows",
      ),
      ("INSERT INTO orders VALUES (DEFAULT, now(), -1)", "insert_seed_rows"),
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].operation, operation)
    assert_eq(r.findings().filter(f => f.code == "PG821").length(), 1)
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
}

///|
test "seed profile does not discard select overriding conflict or returning extensions" {
  for
    sql in [
      "INSERT INTO t SELECT * FROM old", "WITH x AS (SELECT 1) INSERT INTO t VALUES(1)",
      "INSERT INTO t(id) OVERRIDING SYSTEM VALUE VALUES(1)", "INSERT INTO t AS x VALUES(1)",
      "INSERT INTO t(a,A) VALUES(1,2)", "INSERT INTO t(a,b) VALUES(1)", "INSERT INTO t VALUES(1),(1,2)",
      "INSERT INTO t VALUES(custom())", "INSERT INTO t VALUES((SELECT 1))", "INSERT INTO t VALUES(1) ON CONFLICT ON CONSTRAINT pk DO NOTHING",
      "INSERT INTO t VALUES(1) ON CONFLICT(a) WHERE a>0 DO NOTHING", "INSERT INTO t VALUES(1) ON CONFLICT(a) DO UPDATE SET a=1,a=2",
      "INSERT INTO t VALUES(1) ON CONFLICT DO UPDATE SET a=1", "INSERT INTO t VALUES(1) ON CONFLICT(lower(a)) DO NOTHING",
      "INSERT INTO t VALUES(1) RETURNING custom(a)",
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].sql, sql)
  }
  let rows = Array::makei(100, i => "(" + i.to_string() + ")")
  let prefix = "INSERT INTO t(id) VALUES " + rows.join(",")
  assert_true(
    @moonddl_guard.review_sql(
      prefix,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
  assert_false(
    @moonddl_guard.review_sql(
      prefix + ",(101)",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
}

///|
test "seed review composes with ddl locks rollback and full-report replay" {
  let r = @moonddl_guard.review_sql(
    "BEGIN; SAVEPOINT p; ALTER TABLE t ADD n int; INSERT INTO t(id) VALUES(1) ON CONFLICT DO NOTHING; ROLLBACK TO p; INSERT INTO t(id) VALUES(2); COMMIT;",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG803").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG822").length(), 1)
  assert_eq(
    r.to_json(),
    @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
  )
  assert_eq(
    r.to_sarif("migrations/seed.sql"),
    r.to_sarif("migrations/seed.sql"),
  )
  let broken = @moonddl_guard.review_sql(
    "INSERT INTO t SELECT * FROM x; ROLLBACK; INSERT INTO t VALUES(1);",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_false(broken.is_complete())
  assert_eq(broken.statements()[2].operation, "insert_seed_rows")
}
