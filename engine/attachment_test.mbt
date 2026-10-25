///|
fn attachment_review(
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
test "prebuilt unique index attachment retains lock and ownership preconditions" {
  let sql = "SET lock_timeout='1s'; CREATE UNIQUE INDEX CONCURRENTLY email_idx ON public.users(email); ALTER TABLE public.users ADD CONSTRAINT users_email UNIQUE USING INDEX email_idx;"
  let r = attachment_review(sql)
  assert_true(r.is_complete())
  assert_eq(r.exit_code(), 1)
  assert_eq(r.statements()[2].operation, "attach_unique_constraint")
  assert_eq(r.findings().filter(f => f.code == "PG407").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG408").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG409").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG410").length(), 0)
  assert_eq(r.findings().filter(f => f.code == "PG305").length(), 2)
  assert_eq(
    r.to_json(),
    @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
  )
  let grouped = attachment_review(sql, delivery=@moonddl_guard.SimpleQuery)
  assert_eq(grouped.findings().filter(f => f.code == "PG201").length(), 1)
}

///|
test "primary key attachment exposes nullable-key scan condition without assuming catalog data" {
  let r = attachment_review(
    "ALTER TABLE ONLY \"客户\" ADD CONSTRAINT \"主;键\" PRIMARY KEY USING INDEX \"idx;x\";",
  )
  assert_true(r.is_complete())
  assert_eq(r.statements()[0].operation, "attach_primary_key")
  assert_eq(r.findings().map(f => f.code), ["PG407", "PG408", "PG409", "PG410"])
  assert_eq(r.to_sarif("m/attach.sql"), r.to_sarif("m/attach.sql"))
}

///|
test "attachment lock follows commit and savepoint rollback boundaries" {
  for
    (prefix, expected) in [
      ("BEGIN; ALTER TABLE t ADD CONSTRAINT u UNIQUE USING INDEX i;", 1),
      ("BEGIN; ALTER TABLE t ADD CONSTRAINT u UNIQUE USING INDEX i; COMMIT;", 0),
      (
        "BEGIN; SAVEPOINT s; ALTER TABLE t ADD CONSTRAINT u UNIQUE USING INDEX i; ROLLBACK TO s;",
        0,
      ),
      (
        "BEGIN; ALTER TABLE t ADD CONSTRAINT u UNIQUE USING INDEX i; SAVEPOINT s; ROLLBACK TO s;",
        1,
      ),
    ] {
    let r = attachment_review(
      prefix + "ALTER TABLE t VALIDATE CONSTRAINT c; COMMIT;",
    )
    assert_true(r.is_complete())
    assert_eq(r.findings().filter(f => f.code == "PG405").length(), expected)
  }
}

///|
test "attachment grammar does not discard deferrability options or extra actions" {
  for
    sql in [
      "ALTER TABLE t VALIDATE CONSTRAINT \"\";", "ALTER TABLE t ADD CONSTRAINT \"\" CHECK(a > 0);",
      "ALTER TABLE t ADD CONSTRAINT u USING INDEX i;", "ALTER TABLE t ADD CONSTRAINT u UNIQUE USING INDEX schema.i;",
      "ALTER TABLE t ADD CONSTRAINT u PRIMARY USING INDEX i;", "ALTER TABLE t ADD CONSTRAINT u UNIQUE USING INDEX i DEFERRABLE;",
      "ALTER TABLE t ADD CONSTRAINT u UNIQUE USING INDEX i NOT DEFERRABLE;", "ALTER TABLE t ADD CONSTRAINT u UNIQUE USING INDEX i, ADD COLUMN c int;",
      "ALTER TABLE t ADD UNIQUE USING INDEX i;", "ALTER TABLE t ADD CONSTRAINT \"\" UNIQUE USING INDEX i;",
      "ALTER TABLE \"\" ADD CONSTRAINT u UNIQUE USING INDEX i;", "ALTER TABLE t ADD CONSTRAINT u UNIQUE USING INDEX \"\";",
    ] {
    let r = attachment_review(sql)
    assert_false(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].sql, sql)
    assert_eq(r.exit_code(), 2)
  }
}
