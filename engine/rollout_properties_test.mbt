///|
test "bootstrap prefixes round trip without losing malformed source" {
  let source = "CREATE TABLE public.seed (id int PRIMARY KEY, note text NOT NULL DEFAULT 'new'); INSERT INTO public.seed(id,note) VALUES(1,'a') ON CONFLICT(id) DO UPDATE SET note=excluded.note RETURNING id;"
  for end in 0..<=source.length() {
    let input = source[0:end].to_owned()
    let r = @moonddl_guard.review_sql(
      input,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    let first = r.to_json().stringify()
    let replay = @moonddl_guard.decode_report(first)
    assert_eq(first, replay.to_json().stringify())
    assert_eq(r.exit_code(), replay.exit_code())
    assert_eq(r.is_complete(), replay.is_complete())
  }
}

///|
test "unicode rollout preserves source spans across bootstrap data and rename" {
  let sql = "-- 😀\r\nCREATE TABLE public.\"订单\" (\"编号\" int PRIMARY KEY, note text NOT NULL DEFAULT '已支付');\r\nINSERT INTO public.\"订单\"(\"编号\",note) VALUES(1,'😀');\r\nALTER TABLE public.\"订单\" RENAME COLUMN note TO status;"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  assert_eq(r.statements().length(), 3)
  for stmt in r.statements() {
    assert_true(sql.contains(stmt.sql))
    assert_eq(sql[stmt.location.start:stmt.location.end].to_owned(), stmt.sql)
  }
  assert_eq(
    r.to_json(),
    @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
  )
  guard r.to_sarif("迁移/订单.sql") is { "runs": Array(runs), .. } else {
    fail("Missing SARIF")
  }
  guard runs[0] is { "artifacts": Array(artifacts), .. } else {
    fail("Missing retained source")
  }
  assert_true(
    artifacts[0] is { "contents": { "text": String(text), .. }, .. } &&
    text == sql,
  )
}

///|
test "strong lock rename and unknown input compose without leaking between reviews" {
  let prefix = "BEGIN; SAVEPOINT phase; ALTER TABLE parent ADD flag int; CREATE TABLE child(id int REFERENCES parent(id)); ALTER TABLE parent RENAME TO customers; "
  let suffix = "INSERT INTO customers(id) VALUES(1); ROLLBACK TO phase; UPDATE parent SET flag=1 WHERE id=1; COMMIT;"
  let r = @moonddl_guard.review_sql(
    prefix + suffix,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG803").length(), 1)
  let unknown = @moonddl_guard.review_sql(
    prefix + "DO $$ BEGIN NULL; END $$; " + suffix,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_false(unknown.is_complete())
  assert_eq(unknown.findings().filter(f => f.code == "PG803").length(), 0)
  assert_eq(unknown.statements()[5].sql, "DO $$ BEGIN NULL; END $$;")
  assert_true(unknown.findings().any(f => f.code == "PG804"))
  let isolated = @moonddl_guard.review_sql(
    "INSERT INTO customers(id) VALUES(1)",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(
    isolated
    .findings()
    .filter(f => f.code == "PG803" || f.code == "PG804")
    .length(),
    0,
  )
}
