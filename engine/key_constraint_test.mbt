///|
test "direct key constraints report blocking builds null semantics and deferrability" {
  for
    (tail, operation) in [
      ("ADD UNIQUE (a,b)", "add_unique_constraint"),
      (
        "ADD CONSTRAINT uq UNIQUE NULLS NOT DISTINCT (a)", "add_unique_constraint",
      ),
      (
        "ADD CONSTRAINT pk PRIMARY KEY (a) DEFERRABLE INITIALLY DEFERRED", "add_primary_key",
      ),
      (
        "ADD CONSTRAINT uq UNIQUE NULLS DISTINCT (a) NOT DEFERRABLE", "add_unique_constraint",
      ),
    ] {
    let r = @moonddl_guard.review_sql(
      "ALTER TABLE t " + tail,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete(), msg=tail)
    assert_eq(r.statements()[0].operation, operation)
    assert_eq(r.findings().filter(f => f.code == "PG425").length(), 1)
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
}

///|
test "key addition participates in rename backfill and rollback lock workflows" {
  let r = @moonddl_guard.review_sql(
    "BEGIN; ALTER TABLE t ADD CONSTRAINT u UNIQUE (a); ALTER TABLE t RENAME TO n; UPDATE n SET b=1 WHERE id=1; COMMIT;",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(r.findings().filter(f => f.code == "PG803").length(), 1)
  let rollback = @moonddl_guard.review_sql(
    "BEGIN; SAVEPOINT p; ALTER TABLE t ADD PRIMARY KEY (a); ROLLBACK TO p; ALTER TABLE t VALIDATE CONSTRAINT c; COMMIT;",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(rollback.findings().filter(f => f.code == "PG405").length(), 0)
}

///|
test "unsupported direct key options and malformed key lists are retained" {
  for
    tail in [
      "ADD UNIQUE ()", "ADD UNIQUE (a,a)", "ADD UNIQUE (a) NOT VALID", "ADD PRIMARY KEY (a) NOT DEFERRABLE INITIALLY DEFERRED",
      "ADD UNIQUE (a) INCLUDE (b)", "ADD UNIQUE (a), DROP COLUMN b",
    ] {
    let sql = "ALTER TABLE t " + tail
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete(), msg=tail)
    assert_eq(r.statements()[0].sql, sql)
  }
}
