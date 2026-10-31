///|
test "unsupported construct hints preserve full input and exact Unicode locations" {
  for
    (sql, marker, message) in [
      ("-- 😀\r\nDO $$ BEGIN NULL; END $$;", "DO", "procedural"),
      ("REVOKE ALL ON FUNCTION f() FROM PUBLIC;", "REVOKE", "privilege"),
      (
        "CREATE OR REPLACE FUNCTION f() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$;",
        "FUNCTION", "routine",
      ),
      (
        "CREATE FUNCTION f() RETURNS int LANGUAGE sql SECURITY DEFINER AS $$ SELECT 1 $$;",
        "FUNCTION", "routine",
      ),
      ("INSERT INTO t(id) SELECT id FROM old;", "SELECT", "query source"),
      ("CREATE INDEX i ON t(name COLLATE \"C\");", "COLLATE", "COLLATE"),
      ("ALTER TABLE t ADD a int[];", "[", "array"),
      ("ALTER TABLE t ADD a int, DROP b;", ",", "multi-ADD"),
    ] {
    let r = column_review(sql)
    assert_false(r.is_complete())
    assert_eq(r.exit_code(), 2)
    let fs = r.findings().filter(f => f.code == "PG002")
    assert_eq(fs.length(), 1)
    assert_true(fs[0].message.contains(message), msg=sql)
    let loc = fs[0].location
    assert_eq(sql[loc.start:loc.end].to_owned(), marker)
    assert_true(fs[0].action.length() > 30)
    assert_eq(@moonddl_guard.decode_report(r.to_json().stringify()), r)
    assert_true(sql.contains(r.statements()[0].sql))
  }
}

///|
test "unknown fallbacks and supported clauses keep their existing verdicts" {
  let r = column_review("MAGIC t;")
  assert_false(r.is_complete())
  assert_true(
    r
    .findings()
    .any(f => f.code == "PG002" && f.message.has_prefix("Statement or clause")),
  )
  for
    sql in [
      "ALTER TABLE t ADD a int, ADD b int", "INSERT INTO t(id) VALUES(1)", "ALTER TABLE t ADD a text DEFAULT 'SELECT COLLATE []'",
      "CREATE INDEX i ON t(id)",
    ] {
    let r = column_review(sql)
    assert_true(r.is_complete())
    assert_false(r.findings().any(f => f.code == "PG002"))
  }
  let recovered = column_review(
    "DO $$ BEGIN NULL; END $$; COMMIT; BEGIN; ALTER TABLE t ADD a int; COMMIT;",
  )
  assert_false(recovered.is_complete())
  assert_eq(recovered.statements()[3].operation, "add_column")
}

///|
test "compound limit hints do not confuse commas inside literal or array values" {
  let many = Array::makei(33, i => "ADD c" + i.to_string() + " int").join(",")
  let r = column_review("ALTER TABLE t " + many)
  assert_true(
    r.findings().any(f => f.code == "PG002" && f.message.contains("32-action")),
  )
  let array = column_review("ALTER TABLE t ADD a int[] DEFAULT ARRAY[1,2]")
  assert_true(
    array.findings().any(f => f.code == "PG002" && f.message.contains("array")),
  )
  assert_false(array.findings().any(f => f.message.contains("multi-ADD")))
}
