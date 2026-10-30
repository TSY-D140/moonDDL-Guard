///|
test "enum workflow reviews ordering renames and transaction visibility accurately" {
  for
    (sql, operation) in [
      ("CREATE TYPE public.state AS ENUM ('pending','paid','')", "create_enum"),
      ("CREATE TYPE empty AS ENUM ()", "create_enum"),
      (
        "ALTER TYPE public.state ADD VALUE IF NOT EXISTS 'queued' BEFORE 'paid'",
        "add_enum_value",
      ),
      ("ALTER TYPE state ADD VALUE 'done'", "add_enum_value"),
      (
        "ALTER TYPE state RENAME VALUE 'pending' TO 'queued'", "rename_enum_value",
      ),
      ("ALTER TYPE state RENAME TO delivery_state", "rename_type"),
      ("ALTER TYPE public.state SET SCHEMA archive", "move_type_schema"),
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].operation, operation)
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
  for
    (sql, transaction, delivery, level) in [
      (
        "ALTER TYPE state ADD VALUE 'x'",
        @moonddl_guard.Autocommit,
        @moonddl_guard.PerStatement,
        @moonddl_guard.Advisory,
      ),
      (
        "BEGIN; ALTER TYPE state ADD VALUE 'x'; COMMIT;",
        @moonddl_guard.Autocommit,
        @moonddl_guard.PerStatement,
        @moonddl_guard.Warning,
      ),
      (
        "ALTER TYPE state ADD VALUE 'x'; INSERT INTO t VALUES('x');",
        @moonddl_guard.Autocommit,
        @moonddl_guard.SimpleQuery,
        @moonddl_guard.Warning,
      ),
      (
        "ALTER TYPE state ADD VALUE 'x'",
        @moonddl_guard.UnknownTransaction,
        @moonddl_guard.PerStatement,
        @moonddl_guard.Warning,
      ),
    ] {
    let r = @moonddl_guard.review_sql(sql, transaction~, delivery~)
    assert_true(r.is_complete())
    let visibility = r.findings().filter(f => f.code == "PG923")
    assert_eq(visibility.length(), 1)
    assert_eq(visibility[0].severity, level)
    assert_eq(r.findings().filter(f => f.code == "PG201").length(), 0)
  }
}

///|
test "enum bounds reject truncation unknown type clauses and malformed labels" {
  let labels = Array::makei(128, i => "'v" + i.to_string() + "'")
  let sql = "CREATE TYPE t AS ENUM (" + labels.join(",") + ")"
  assert_true(
    @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
  let label63 = "界".repeat(21)
  assert_true(
    @moonddl_guard.review_sql(
      "ALTER TYPE t ADD VALUE '" + label63 + "'",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
  for
    sql in [
      "CREATE TYPE t AS ENUM (" + labels.join(",") + ",'overflow')",
      "ALTER TYPE t ADD VALUE '" + label63 + "a'",
      "CREATE TYPE t AS ENUM ('a','a')",
      "CREATE TYPE t AS ENUM ('a',)",
      "CREATE TYPE t AS ENUM (NULL)",
      "ALTER TYPE t ADD VALUE 'a' BEFORE",
      "ALTER TYPE t ADD VALUE 'a' BEFORE 'b' CASCADE",
      "ALTER TYPE t DROP VALUE 'a'",
      "ALTER TYPE t RENAME VALUE 'a' TO 'b' CASCADE",
      "ALTER TYPE t RENAME TO public.x",
      "CREATE TYPE t AS (a int)",
      "CREATE TYPE t AS RANGE (SUBTYPE=int)",
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].sql, sql)
  }
}

///|
test "enum source and reports are deterministic through recovery and deltas" {
  let source = "CREATE TYPE state AS ENUM ('pending','paid'); ALTER TYPE state ADD VALUE 'queued' BEFORE 'paid';"
  for end in 0..<=source.length() {
    let prefix = source[0:end].to_owned()
    let parsed = @moonddl_guard.review_sql(
      prefix,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_eq(
      parsed.to_json(),
      @moonddl_guard.decode_report(parsed.to_json().stringify()).to_json(),
    )
  }
  let r = @moonddl_guard.review_sql(
    "ALTER TYPE t DROP VALUE 'a'; ROLLBACK; ALTER TYPE t RENAME VALUE 'a' TO 'b';",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_false(r.is_complete())
  assert_eq(r.statements()[2].operation, "rename_enum_value")
  assert_eq(
    r.to_json(),
    @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
  )
  assert_eq(
    r.to_sarif("migrations/enum.sql"),
    r.to_sarif("migrations/enum.sql"),
  )
  let complete = @moonddl_guard.review_sql(
    "ALTER TYPE t ADD VALUE 'a'",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  let delta = @moonddl_guard.compare_reviews(complete, complete)
  assert_eq(
    delta.to_json(),
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
  )
}
