///|
fn check_review(
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
test "CHECK phases distinguish blocking scan and postponed data validation" {
  let r = check_review(
    "SET lock_timeout='1s'; ALTER TABLE public.orders ADD CONSTRAINT positive CHECK (amount >= 0) NOT VALID; ALTER TABLE public.orders VALIDATE CONSTRAINT positive;",
  )
  assert_true(r.is_complete())
  assert_eq(r.exit_code(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG401").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG403").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG404").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG405").length(), 0)
  assert_eq(r.findings().filter(f => f.code == "PG305").length(), 2)
  assert_eq(
    r.to_json(),
    @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
  )
  let immediate = check_review(
    "ALTER TABLE orders ADD CONSTRAINT positive CHECK (amount >= 0);",
  )
  assert_eq(immediate.findings().map(f => f.code), ["PG401", "PG402", "PG406"])
}

///|
test "same transaction or query grouping retains strong ADD lock" {
  let phases = "ALTER TABLE t ADD CONSTRAINT c CHECK (a IS NOT NULL) NOT VALID; ALTER TABLE t VALIDATE CONSTRAINT c;"
  let batch = check_review(phases, delivery=@moonddl_guard.SimpleQuery)
  assert_eq(batch.findings().filter(f => f.code == "PG405").length(), 1)
  let active = check_review("BEGIN; " + phases + " COMMIT;")
  assert_eq(active.findings().filter(f => f.code == "PG405").length(), 1)
  for end in ["COMMIT", "ROLLBACK", "COMMIT AND CHAIN", "ROLLBACK AND CHAIN"] {
    let r = check_review(
      "BEGIN; ALTER TABLE t ADD CONSTRAINT c CHECK (a > 0) NOT VALID; " +
      end +
      "; ALTER TABLE t VALIDATE CONSTRAINT c; COMMIT;",
    )
    assert_eq(r.findings().filter(f => f.code == "PG405").length(), 0, msg=end)
  }
}

///|
test "table identities respect quoting schema and ASCII folding" {
  for
    (added, validated, matches) in [
      ("PUBLIC.Orders", "public.orders", true),
      ("\"public\".\"orders\"", "public.orders", true),
      ("\"Orders\"", "orders", false),
      ("public.orders", "other.orders", false),
      ("\"a.b\"", "a.b", false),
      ("t", "public.t", false),
      ("\"😀;表\"", "\"😀;表\"", true),
    ] {
    let r = check_review(
      "BEGIN; ALTER TABLE " +
      added +
      " ADD CONSTRAINT c CHECK (a > 0) NOT VALID; ALTER TABLE " +
      validated +
      " VALIDATE CONSTRAINT c; COMMIT;",
    )
    assert_true(r.is_complete(), msg=added)
    assert_eq(
      r.findings().filter(f => f.code == "PG405").length(),
      if matches {
        1
      } else {
        0
      },
    )
  }
}

///|
test "CHECK predicate bounds malformed and unknown clauses are preserved" {
  for
    tail in [
      "CHECK (a > 0) NOT VALID", "CHECK (a IS NOT NULL AND b < 1)", "CHECK (lower(email) <> '') NOT VALID",
      "CHECK ((a + b) > 0)",
    ] {
    assert_true(
      check_review("ALTER TABLE ONLY t ADD CONSTRAINT c " + tail).is_complete(),
      msg=tail,
    )
  }
  for
    tail in [
      "CHECK ()", "CHECK (a > 0", "CHECK (custom(a))", "CHECK (EXISTS (SELECT 1))",
      "CHECK (a > 0) NOT ENFORCED", "CHECK (a > 0) NO INHERIT", "CHECK (a > 0), ADD COLUMN b int",
      "FOREIGN KEY (a) REFERENCES t(a) NOT VALID", "CHECK (a::int > 0)", "CHECK (a > 0) BOGUS",
    ] {
    let sql = "ALTER TABLE t ADD CONSTRAINT c " + tail + ";"
    let r = check_review(sql)
    assert_false(r.is_complete(), msg=tail)
    assert_eq(r.statements()[0].sql, sql)
  }
  for
    sql in [
      "ALTER TABLE t VALIDATE CONSTRAINT c extra", "ALTER TABLE IF EXISTS t VALIDATE CONSTRAINT c",
    ] {
    assert_false(check_review(sql).is_complete())
  }
}

///|
test "unknown SQL never leaves a complete verdict or fabricated retained lock" {
  let sql = "BEGIN; ALTER TABLE t ADD CONSTRAINT c CHECK (a > 0) NOT VALID; SELECT 1; ALTER TABLE t VALIDATE CONSTRAINT c; ROLLBACK; CREATE INDEX CONCURRENTLY x ON t(a);"
  let r = check_review(sql)
  assert_false(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG405").length(), 0)
  assert_eq(r.statements()[5].coverage, @moonddl_guard.Analyzed)
  assert_eq(
    r.to_json(),
    @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
  )
}
