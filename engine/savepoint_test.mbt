///|
fn point_review(sql : String) -> @moonddl_guard.Review {
  @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
}

///|
test "savepoint rollback restores timeout snapshots and keeps outer transaction" {
  let r = point_review(
    "SET lock_timeout='2s'; BEGIN; SAVEPOINT s; SET lock_timeout='3s'; SET LOCAL statement_timeout='1s'; ROLLBACK TO SAVEPOINT s; CREATE INDEX x ON t(a); COMMIT; CREATE INDEX y ON t(a);",
  )
  assert_true(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG305").map(f => f.message), [
    "Effective lock_timeout is 2000ms for this index.", "Effective lock_timeout is 2000ms for this index.",
  ])
  assert_eq(r.findings().filter(f => f.code == "PG303").length(), 2)
  assert_eq(
    r.to_json(),
    @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
  )
  let active = point_review(
    "BEGIN; SAVEPOINT s; ROLLBACK TO s; CREATE INDEX CONCURRENTLY x ON t(a); COMMIT;",
  )
  assert_eq(active.findings().filter(f => f.code == "PG201").length(), 1)
}

///|
test "duplicate savepoint names shadow and release merges rather than rolls back" {
  let r = point_review(
    "BEGIN; SET lock_timeout='1s'; SAVEPOINT s; SET lock_timeout='2s'; SAVEPOINT s; SET lock_timeout='3s'; ROLLBACK TO s; CREATE INDEX x ON t(a); RELEASE s; ROLLBACK TO s; CREATE INDEX y ON t(a); COMMIT;",
  )
  assert_true(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG305").map(f => f.message), [
    "Effective lock_timeout is 2000ms for this index.", "Effective lock_timeout is 1000ms for this index.",
  ])
  let merged = point_review(
    "BEGIN; SAVEPOINT a; SET lock_timeout='3s'; SAVEPOINT b; RELEASE SAVEPOINT a; CREATE INDEX x ON t(a); COMMIT;",
  )
  assert_true(merged.is_complete())
  assert_eq(
    merged.findings().filter(f => f.code == "PG305")[0].message,
    "Effective lock_timeout is 3000ms for this index.",
  )
}

///|
test "savepoint rollback releases only strong locks acquired since the point" {
  for
    (before, after, expected) in [
      ("", "ALTER TABLE t ADD CONSTRAINT c CHECK(a>0) NOT VALID;", 0),
      ("ALTER TABLE t ADD CONSTRAINT c CHECK(a>0) NOT VALID;", "", 1),
    ] {
    let r = point_review(
      "BEGIN;" +
      before +
      "SAVEPOINT s;" +
      after +
      "ROLLBACK TO s; ALTER TABLE t VALIDATE CONSTRAINT c; COMMIT;",
    )
    assert_eq(r.findings().filter(f => f.code == "PG405").length(), expected)
    assert_true(r.is_complete())
  }
}

///|
test "unknown inherited released and implicit savepoint scopes never pass" {
  for
    sql in [
      "SAVEPOINT s;", "BEGIN; ROLLBACK TO s;", "BEGIN; SAVEPOINT s; RELEASE s; ROLLBACK TO s;",
      "BEGIN; SAVEPOINT a; SAVEPOINT b; ROLLBACK TO a; RELEASE b;", "BEGIN; SAVEPOINT s; COMMIT; BEGIN; ROLLBACK TO s;",
      "BEGIN; SAVEPOINT s; SELECT 1; ROLLBACK TO s;", "BEGIN; SAVEPOINT s extra;",
      "BEGIN; RELEASE SAVEPOINT s extra;",
    ] {
    assert_false(point_review(sql).is_complete(), msg=sql)
  }
  let implicit = @moonddl_guard.review_sql(
    "SAVEPOINT s; CREATE INDEX x ON t(a);",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.SimpleQuery,
  )
  assert_false(implicit.is_complete())
  let inherited = @moonddl_guard.review_sql(
    "SAVEPOINT s; ROLLBACK TRANSACTION TO SAVEPOINT s; RELEASE s;",
    transaction=@moonddl_guard.Active,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(inherited.is_complete())
}

///|
test "savepoint limits quoted names and post-error recovery are bounded" {
  let sql = StringBuilder()
  sql.write_string("BEGIN;")
  for i in 0..<64 {
    sql.write_string("SAVEPOINT s\{i};")
  }
  let exact = point_review(sql.to_string() + "ROLLBACK;")
  assert_true(exact.is_complete())
  let over = point_review(
    sql.to_string() +
    "SAVEPOINT extra; ROLLBACK; CREATE INDEX CONCURRENTLY x ON t(a);",
  )
  assert_false(over.is_complete())
  assert_eq(
    over.statements()[over.statements().length() - 1].coverage,
    @moonddl_guard.Analyzed,
  )
  assert_true(
    point_review(
      "BEGIN; SAVEPOINT \"😀;点\"; ROLLBACK WORK TO \"😀;点\"; RELEASE \"😀;点\"; COMMIT;",
    ).is_complete(),
  )
  assert_false(point_review("BEGIN; SAVEPOINT \"X\"; RELEASE x;").is_complete())
  for n in [63, 64] {
    let name = StringBuilder()
    for _ in 0..<n {
      name.write_string("a")
    }
    assert_eq(
      point_review("BEGIN; SAVEPOINT " + name.to_string() + "; COMMIT;").is_complete(),
      n == 63,
    )
  }
}
