///|
fn nullable_review(
  sql : String,
  delivery~ : @moonddl_guard.Delivery = @moonddl_guard.PerStatement,
) -> @moonddl_guard.Review {
  @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery~,
  )
}

///|
test "NOT NULL tightening and relaxation expose distinct data risks" {
  for
    (sql, operation, code) in [
      (
        "ALTER TABLE public.users ALTER COLUMN email SET NOT NULL;", "set_not_null",
        "PG412",
      ),
      (
        "ALTER TABLE ONLY \"客户\" ALTER \"邮箱;地址\" DROP NOT NULL;", "drop_not_null",
        "PG413",
      ),
    ] {
    let r = nullable_review(sql)
    assert_true(r.is_complete(), msg=sql)
    assert_eq(r.exit_code(), 1)
    assert_eq(r.statements()[0].operation, operation)
    assert_eq(r.statements()[0].sql, sql)
    assert_eq(r.findings().map(f => f.code), ["PG411", code, "PG414"])
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
}

///|
test "CHECK workflow never fabricates a no-scan catalog proof" {
  let r = nullable_review(
    "SET lock_timeout='1s'; ALTER TABLE t ADD CONSTRAINT c CHECK(a IS NOT NULL) NOT VALID; ALTER TABLE t VALIDATE CONSTRAINT c; ALTER TABLE t ALTER COLUMN a SET NOT NULL;",
  )
  assert_true(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG412").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG414").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG305").length(), 3)
  assert_eq(r.findings().filter(f => f.code == "PG405").length(), 0)
  let grouped = nullable_review(
    "ALTER TABLE t ALTER a SET NOT NULL; ALTER TABLE t VALIDATE CONSTRAINT c;",
    delivery=@moonddl_guard.SimpleQuery,
  )
  assert_eq(grouped.findings().filter(f => f.code == "PG405").length(), 1)
}

///|
test "nullability locks compose with savepoint commit and rollback" {
  for
    (prefix, expected) in [
      ("BEGIN; ALTER TABLE t ALTER a SET NOT NULL;", 1),
      ("BEGIN; ALTER TABLE t ALTER a DROP NOT NULL; COMMIT;", 0),
      (
        "BEGIN; SAVEPOINT s; ALTER TABLE t ALTER a SET NOT NULL; ROLLBACK TO s;",
        0,
      ),
      (
        "BEGIN; ALTER TABLE t ALTER a SET NOT NULL; SAVEPOINT s; ROLLBACK TO s;",
        1,
      ),
    ] {
    let r = nullable_review(
      prefix + "ALTER TABLE t VALIDATE CONSTRAINT c; COMMIT;",
    )
    assert_true(r.is_complete())
    assert_eq(r.findings().filter(f => f.code == "PG405").length(), expected)
  }
}

///|
test "unsupported nullability options malformed names and extra ALTER actions are retained" {
  for
    sql in [
      "ALTER TABLE t ALTER COLUMN a SET NOT NULL NOT VALID;", "ALTER TABLE t ALTER COLUMN a SET NOT NULL, ALTER COLUMN b SET NOT NULL;",
      "ALTER TABLE IF EXISTS t ALTER a SET NOT NULL;", "ALTER TABLE t ALTER a DROP NOT NULL CASCADE;",
      "ALTER TABLE t ALTER a SET NULL;", "ALTER TABLE t ALTER a SET DEFAULT NULL;",
      "ALTER TABLE t ALTER \"\" SET NOT NULL;", "ALTER TABLE t ALTER a SET NOT;",
      "ALTER TABLE t ALTER a SET NOT NULL trailing;",
    ] {
    let r = nullable_review(sql)
    assert_false(r.is_complete(), msg=sql)
    assert_eq(r.exit_code(), 2)
    assert_eq(r.statements()[0].sql, sql)
  }
  let recovery = nullable_review(
    "ALTER TABLE t ALTER a SET NOT NULL future; ROLLBACK; ALTER TABLE t ALTER a DROP NOT NULL;",
  )
  assert_false(recovery.is_complete())
  assert_eq(recovery.statements()[2].coverage, @moonddl_guard.Analyzed)
  assert_eq(recovery.findings().filter(f => f.code == "PG413").length(), 1)
}

///|
test "nullability findings remain visible in baseline gates and SARIF" {
  let before = nullable_review("")
  let after = nullable_review("ALTER TABLE t ALTER a DROP NOT NULL;")
  let delta = @moonddl_guard.compare_reviews(before, after)
  assert_eq(delta.exit_code(), 1)
  assert_eq(delta.introduced().length(), 3)
  assert_eq(
    delta.to_json(),
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
  )
  let sarif = after.to_sarif("migrations/nonnull.sql")
  assert_eq(sarif, @json.parse(sarif.stringify()))
}
