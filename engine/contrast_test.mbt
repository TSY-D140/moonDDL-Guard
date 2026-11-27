///|
test "paired rewrite warnings distinguish defaults from backfill effects" {
  for
    (sql, present, absent) in [
      ("ALTER TABLE t ADD stamp timestamptz DEFAULT now();", "PG502", "PG503"),
      (
        "ALTER TABLE t ADD stamp timestamptz DEFAULT clock_timestamp();", "PG503",
        "PG502",
      ),
      (
        "ALTER TABLE t ALTER stamp SET DEFAULT clock_timestamp();", "PG512", "PG503",
      ),
      (
        "ALTER TABLE t ADD calc int GENERATED ALWAYS AS (a*2) STORED;", "PG514",
        "PG516",
      ),
      (
        "ALTER TABLE t ADD calc int GENERATED ALWAYS AS (a*2) VIRTUAL;", "PG516",
        "PG514",
      ),
    ] {
    for prefix in ["", "-- 😀 preserve SQL\r\n", "/* review */\n"] {
      let r = @moonddl_guard.review_sql(
        prefix + sql,
        transaction=@moonddl_guard.Autocommit,
        delivery=@moonddl_guard.PerStatement,
      )
      assert_true(r.is_complete(), msg=sql)
      assert_true(r.findings().any(f => f.code == present), msg=sql)
      assert_false(r.findings().any(f => f.code == absent), msg=sql)
      assert_eq(
        r.to_json(),
        @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
      )
    }
  }
}

///|
test "WHERE and transaction contrasts do not imply row-count or lock-free safety" {
  for
    (predicate, all_rows) in [
      ("", true),
      (" WHERE TRUE", true),
      (" WHERE FALSE", false),
      (" WHERE id=1", false),
    ] {
    let r = @moonddl_guard.review_sql(
      "UPDATE t SET n=n+1" + predicate + ";",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete())
    assert_eq(r.findings().any(f => f.code == "PG802"), all_rows)
    assert_true(r.findings().any(f => f.code == "PG801"))
    assert_false(r.findings().any(f => f.code == "PG804"))
  }
  for
    (delivery, blocked) in [
      (@moonddl_guard.PerStatement, false),
      (@moonddl_guard.SimpleQuery, true),
    ] {
    let r = @moonddl_guard.review_sql(
      "CREATE INDEX CONCURRENTLY i ON t(id); UPDATE t SET n=1 WHERE FALSE;",
      transaction=@moonddl_guard.Autocommit,
      delivery~,
    )
    assert_eq(r.findings().any(f => f.code == "PG201"), blocked)
    assert_eq(r.findings().any(f => f.code == "PG804"), blocked)
    assert_false(r.findings().any(f => f.code == "PG101"))
  }
}

///|
test "NOT VALID and split phases suppress only the corresponding scan retention claims" {
  for (suffix, scan) in [("", true), (" NOT VALID", false)] {
    let sql = "ALTER TABLE t ADD CONSTRAINT c CHECK(a>0)" +
      suffix +
      "; ALTER TABLE t VALIDATE CONSTRAINT c;"
    for
      (delivery, retained) in [
        (@moonddl_guard.PerStatement, false),
        (@moonddl_guard.SimpleQuery, true),
      ] {
      let r = @moonddl_guard.review_sql(
        sql,
        transaction=@moonddl_guard.Autocommit,
        delivery~,
      )
      assert_true(r.is_complete())
      assert_eq(r.findings().any(f => f.code == "PG402"), scan)
      assert_eq(r.findings().any(f => f.code == "PG405"), retained)
      assert_true(r.findings().any(f => f.code == "PG401"))
      assert_true(r.findings().any(f => f.code == "PG404"))
    }
  }
}
