///|
test "every truncated new grammar input remains deterministic and strictly replayable" {
  for
    sql in [
      "ALTER TABLE orders ADD CONSTRAINT fk FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;",
      "ALTER TABLE orders ADD COLUMN stamp timestamptz DEFAULT clock_timestamp() NOT NULL;",
      "ALTER TABLE orders ALTER COLUMN amount TYPE numeric(12,2) USING amount::numeric(12,2);",
      "ALTER TABLE orders DROP CONSTRAINT IF EXISTS old CASCADE;", "TRUNCATE TABLE ONLY orders, events RESTART IDENTITY CASCADE;",
    ] {
    for i in 0..<=sql.length() {
      let prefix = sql[:i].to_owned()
      let r = @moonddl_guard.review_sql(
        prefix,
        transaction=@moonddl_guard.Autocommit,
        delivery=@moonddl_guard.PerStatement,
      )
      assert_eq(
        r.to_json(),
        @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
        msg=prefix,
      )
      guard r.to_json() is { "source": String(retained), .. } else {
        fail("Missing original source")
      }
      assert_eq(retained, prefix)
    }
  }
}

///|
test "new migration diagnostics retain rule registration through generic SARIF export" {
  for
    sql in [
      "ALTER TABLE t ADD COLUMN a timestamp DEFAULT now(); ALTER TABLE t ADD COLUMN b int NOT NULL; ALTER TABLE t ADD COLUMN c app.domain;",
      "ALTER TABLE t ALTER COLUMN a TYPE bigint; ALTER TABLE t ALTER COLUMN b DROP DEFAULT;",
      "DROP TABLE t CASCADE; TRUNCATE t RESTART IDENTITY CASCADE; ALTER TABLE t DROP CONSTRAINT c;",
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete())
    guard r.to_sarif("migrations/all.sql") is { "runs": Array(runs), .. } else {
      fail("Missing runs")
    }
    guard runs[0]
      is { "tool": { "driver": { "rules": Array(rules), .. }, .. }, .. } else {
      fail("Missing rules")
    }
    for f in r.findings() {
      assert_true(
        rules.any(rule => rule is { "id": String(code), .. } && code == f.code),
        msg=f.code,
      )
    }
  }
}

///|
test "tracked relation identities reject UTF8 truncation aliases at the 63 byte boundary" {
  let ascii = StringBuilder()
  let unicode = StringBuilder()
  for _ in 0..<63 {
    ascii.write_string("a")
  }
  for _ in 0..<21 {
    unicode.write_string("表")
  }
  for name in [ascii.to_string(), unicode.to_string()] {
    for
      (prefix, suffix) in [
        ("ALTER TABLE \"", "\" ADD COLUMN a int;"),
        ("ALTER TABLE t ADD FOREIGN KEY (a) REFERENCES \"", "\" (id);"),
        ("DROP TABLE \"", "\";"),
        ("TRUNCATE \"", "\";"),
      ] {
      let valid = @moonddl_guard.review_sql(
        prefix + name + suffix,
        transaction=@moonddl_guard.Autocommit,
        delivery=@moonddl_guard.PerStatement,
      )
      assert_true(valid.is_complete())
      let too_long = prefix + name + "a" + suffix
      let rejected = @moonddl_guard.review_sql(
        too_long,
        transaction=@moonddl_guard.Autocommit,
        delivery=@moonddl_guard.PerStatement,
      )
      assert_false(rejected.is_complete())
      assert_eq(rejected.statements()[0].sql, too_long)
    }
  }
}
