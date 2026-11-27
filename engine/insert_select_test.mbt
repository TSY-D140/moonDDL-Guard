///|
test "bounded table and literal-source backfills retain risks and source" {
  for
    sql in [
      "INSERT INTO dst(id,n) SELECT id,n FROM src WHERE id>100 ON CONFLICT(id) DO NOTHING RETURNING id;",
      "INSERT INTO dst(id,n) SELECT gen_random_uuid(), upper(n) FROM public.src AS s;",
      "INSERT INTO dst(id,n) SELECT gen_random_uuid(),n FROM (VALUES ('a'),('b')) AS v(n) ON CONFLICT(id) DO UPDATE SET n=excluded.n;",
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete(), msg=sql)
    assert_eq(r.exit_code(), 1)
    assert_true(r.findings().any(f => f.code == "PG823"))
    assert_true(r.findings().any(f => f.code == "PG824"))
    assert_false(r.findings().any(f => f.code == "PG804"))
    assert_eq(r.statements()[0].sql, sql)
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
    assert_eq(@moonddl_guard.compare_reviews(r, r).exit_code(), 0)
  }
}

///|
test "backfill rejects every unassessed query extension as a whole" {
  for
    sql in [
      "INSERT INTO dst SELECT id FROM src", "INSERT INTO dst(id) SELECT * FROM src",
      "INSERT INTO dst(id) SELECT DISTINCT id FROM src", "INSERT INTO dst(id) SELECT id FROM src LIMIT 10",
      "INSERT INTO dst(id) SELECT id FROM src ORDER BY id", "INSERT INTO dst(id) SELECT count(*) FROM src",
      "INSERT INTO dst(id) SELECT id FROM src GROUP BY id", "INSERT INTO dst(id) SELECT id FROM src FOR UPDATE",
      "INSERT INTO dst(id) SELECT id FROM src UNION SELECT id FROM other", "INSERT INTO dst(id) SELECT (SELECT id FROM x) FROM src",
      "INSERT INTO dst(id) SELECT custom(id) FROM src", "INSERT INTO dst(id) SELECT id FROM src JOIN other USING(id)",
      "INSERT INTO dst(id) SELECT id FROM (SELECT id FROM src) q", "WITH q AS (SELECT id FROM src) INSERT INTO dst(id) SELECT id FROM q",
      "INSERT INTO dst(id) SELECT uuid() FROM src", "INSERT INTO dst(id) SELECT gen_random_uuid(1) FROM src",
      "INSERT INTO dst(id) SELECT id FROM src WHERE custom(id)", "INSERT INTO dst(id) SELECT id FROM src ON CONFLICT ON CONSTRAINT pk DO NOTHING",
      "INSERT INTO dst(id) SELECT id FROM (VALUES (1),(1,2)) v(id)", "INSERT INTO dst(id) SELECT id FROM (VALUES (x)) v(id)",
      "INSERT INTO dst(id) SELECT id FROM (VALUES (1)) v", "INSERT INTO dst(id) SELECT a FROM (VALUES (1,2)) v(a,A)",
      "INSERT INTO dst(id,id) SELECT id,id FROM src", "INSERT INTO dst(id,n) SELECT id FROM src",
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete(), msg=sql)
    assert_eq(r.exit_code(), 2)
    assert_eq(r.statements()[0].sql, sql)
  }
}

///|
test "backfill bounds and retained source lock restore through savepoints" {
  let rows = Array::makei(100, i => "(" + i.to_string() + ")").join(",")
  let base = "INSERT INTO dst(id) SELECT n FROM (VALUES "
  for (tail, complete) in [(rows, true), (rows + ",(101)", false)] {
    let r = @moonddl_guard.review_sql(
      base + tail + ") v(n)",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_eq(r.is_complete(), complete)
  }
  for
    (prefix, held) in [
      ("BEGIN; ALTER TABLE src ADD a int;", true),
      ("BEGIN; SAVEPOINT s; ALTER TABLE src ADD a int; ROLLBACK TO s;", false),
      ("BEGIN; ALTER TABLE src ADD a int; COMMIT;", false),
    ] {
    let r = @moonddl_guard.review_sql(
      prefix + " INSERT INTO dst(id) SELECT id FROM src;",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete())
    assert_eq(r.findings().any(f => f.code == "PG825"), held)
  }
}

///|
test "backfill prefix fuzz replay and malformed-input recovery preserve behavior" {
  let sql = "-- 😀\r\nINSERT INTO dst(id) SELECT id FROM src WHERE id>0;"
  for end in 0..<=sql.length() {
    let input = sql[0:end].to_owned()
    let r = @moonddl_guard.review_sql(
      input,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
  let r = @moonddl_guard.review_sql(
    "INSERT INTO dst(id) SELECT custom() FROM src; COMMIT; INSERT INTO dst(id) SELECT id FROM src;",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_false(r.is_complete())
  assert_eq(r.statements()[2].operation, "insert_select_rows")
  assert_false(r.findings().any(f => f.code == "PG804" && f.statement == 3))
}
