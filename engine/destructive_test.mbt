///|
fn destructive_review(sql : String) -> @moonddl_guard.Review {
  @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
}

///|
test "destructive review distinguishes data removal protection and sequence restart" {
  for
    (sql, operation, codes) in [
      (
        "DROP TABLE public.legacy, \"旧表😀\" RESTRICT",
        "drop_table",
        ["PG601", "PG602", "PG604"],
      ),
      (
        "DROP TABLE IF EXISTS legacy CASCADE",
        "drop_table",
        ["PG601", "PG602", "PG603", "PG604"],
      ),
      (
        "ALTER TABLE ONLY t DROP COLUMN IF EXISTS old CASCADE",
        "drop_column",
        ["PG601", "PG602", "PG603", "PG604"],
      ),
      (
        "ALTER TABLE t DROP old RESTRICT",
        "drop_column",
        ["PG601", "PG602", "PG604"],
      ),
      (
        "ALTER TABLE t DROP CONSTRAINT IF EXISTS fk CASCADE",
        "drop_constraint",
        ["PG601", "PG605", "PG603", "PG604"],
      ),
      (
        "TRUNCATE TABLE ONLY t, public.logs * RESTART IDENTITY CASCADE",
        "truncate_table",
        ["PG601", "PG602", "PG607", "PG606", "PG603", "PG604"],
      ),
      (
        "TRUNCATE t CONTINUE IDENTITY RESTRICT",
        "truncate_table",
        ["PG601", "PG602", "PG607", "PG604"],
      ),
    ] {
    let r = destructive_review(sql)
    assert_true(r.is_complete(), msg=sql)
    assert_eq(r.exit_code(), 1)
    assert_eq(r.statements()[0].operation, operation)
    assert_eq(r.findings().map(f => f.code), codes)
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
}

///|
test "destructive grammar rejects truncated conflicting and unrelated commands" {
  for
    sql in [
      "DROP TABLE", "DROP TABLE a,", "DROP TABLE a RESTRICT CASCADE", "DROP TABLE \"\"",
      "DROP VIEW v CASCADE", "ALTER TABLE t DROP COLUMN", "ALTER TABLE t DROP CONSTRAINT",
      "ALTER TABLE t DROP COLUMN a, DROP COLUMN b", "TRUNCATE ONLY t *", "TRUNCATE t RESTART",
      "TRUNCATE t RESTART IDENTITY CONTINUE IDENTITY", "TRUNCATE t CASCADE RESTRICT",
    ] {
    let r = destructive_review(sql)
    assert_false(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].sql, sql)
    assert_eq(r.exit_code(), 2)
  }
  let names = StringBuilder()
  for i in 0..<33 {
    if i > 0 {
      names.write_string(",")
    }
    names.write_string("t\{i}")
  }
  assert_false(
    destructive_review("DROP TABLE " + names.to_string()).is_complete(),
  )
}

///|
test "destructive locks survive release and disappear after savepoint rollback" {
  for
    sql in [
      "DROP TABLE t;", "ALTER TABLE t DROP a;", "ALTER TABLE t DROP CONSTRAINT c;",
      "TRUNCATE t;",
    ] {
    for (control, count) in [("RELEASE p", 1), ("ROLLBACK TO p", 0)] {
      let r = destructive_review(
        "BEGIN; SAVEPOINT p; " +
        sql +
        control +
        "; ALTER TABLE t VALIDATE CONSTRAINT v; COMMIT;",
      )
      assert_true(r.is_complete())
      assert_eq(r.findings().filter(f => f.code == "PG405").length(), count)
    }
  }
}

///|
test "destructive reports keep source risks deterministic export and delta replay" {
  let r = destructive_review(
    "-- 😀\r\nDROP TABLE old CASCADE; TRUNCATE logs RESTART IDENTITY;",
  )
  let delta = @moonddl_guard.compare_reviews(destructive_review(""), r)
  assert_eq(delta.exit_code(), 1)
  assert_eq(
    delta.to_json(),
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
  )
  assert_eq(
    r.to_sarif("migrations/remove.sql"),
    r.to_sarif("migrations/remove.sql"),
  )
  let unknown = destructive_review(
    "DROP TABLE old unknown; ROLLBACK; DROP TABLE old;",
  )
  assert_false(unknown.is_complete())
  assert_eq(unknown.statements()[2].operation, "drop_table")
}
