///|
test "combined ordinary adds preserve one statement and column source locations" {
  let sql = "-- 标题😀\r\n  ALTER TABLE ONLY orders ADD \"备注😀\" numeric(12,2) DEFAULT 0,\r\n  ADD COLUMN label text DEFAULT 'x, ADD ignored int' NOT NULL;"
  let r = column_review(sql)
  assert_true(r.is_complete())
  assert_eq(r.statements().length(), 1)
  assert_eq(r.statements()[0].operation, "add_columns")
  assert_eq(r.findings().filter(f => f.code == "PG501").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG521").length(), 1)
  let checks = r.findings().filter(f => f.code == "PG506")
  assert_eq(checks.length(), 1)
  assert_eq(checks[0].statement, 1)
  assert_eq(checks[0].location.line, 3)
  assert_eq(checks[0].location.column, 3)
  let loc = checks[0].location
  assert_eq(
    sql[loc.start:loc.end],
    "ADD COLUMN label text DEFAULT 'x, ADD ignored int' NOT NULL",
  )
  assert_eq(@moonddl_guard.decode_report(r.to_json().stringify()), r)
}

///|
test "combined defaults report per column and shared rewrite effects" {
  let r = column_review(
    "ALTER TABLE orders ADD a int DEFAULT 1 NOT NULL, ADD b timestamptz DEFAULT (now()), ADD c double precision DEFAULT random(), ADD IF NOT EXISTS d text DEFAULT 'a,b'",
  )
  assert_true(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG501").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG503").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG502").length(), 3)
  assert_eq(r.findings().filter(f => f.code == "PG505").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG508").length(), 1)
  assert_true(
    r.findings().any(f => f.code == "PG521" && f.message.contains("volatile")),
  )
  let domain = column_review("ALTER TABLE t ADD a public.amount, ADD b int")
  assert_true(domain.is_complete())
  assert_true(
    domain
    .findings()
    .any(f => f.code == "PG521" && f.message.contains("unresolved")),
  )
}

///|
test "combined additions reject every unsupported or malformed action atomically" {
  for
    tail in [
      "DROP COLUMN b", "ALTER b TYPE bigint", "ADD b serial", "ADD b int GENERATED ALWAYS AS IDENTITY",
      "ADD b int GENERATED ALWAYS AS (a*2) VIRTUAL", "ADD b int REFERENCES parent(id)",
      "ADD b int DEFAULT custom()", "ADD b int[]", "ADD b int CHECK (b>0)", "ADD b int,",
      ", ADD b int", "ADD b numeric(12,2", "ADD b int)", "ADD a int", "ADD \"a\" int",
      "ADD COLUMN", "ADD b int DEFAULT", "ADD b int, DROP c",
    ] {
    let sql = "ALTER TABLE t ADD a int, " + tail + ";"
    let r = column_review(sql)
    assert_false(r.is_complete(), msg=tail)
    assert_eq(r.exit_code(), 2)
    assert_eq(r.statements()[0].sql, sql)
    assert_false(
      r
      .findings()
      .any(f => f.code == "PG501" || f.code == "PG502" || f.code == "PG521"),
      msg=tail,
    )
  }
}

///|
test "combined adds enforce action identifier and nesting boundaries" {
  assert_true(
    column_review("ALTER TABLE t ADD \"a,b\" text DEFAULT 'a''b,c', ADD b int").is_complete(),
  )
  let wide = "界".repeat(21)
  assert_true(
    column_review("ALTER TABLE t ADD \"" + wide + "\" int, ADD b int").is_complete(),
  )
  assert_false(
    column_review("ALTER TABLE t ADD \"" + wide + "界\" int, ADD b int").is_complete(),
  )
  let actions = Array::makei(32, i => "ADD c" + i.to_string() + " int")
  assert_true(
    column_review("ALTER TABLE t " + actions.join(", ")).is_complete(),
  )
  actions.push("ADD extra int")
  assert_false(
    column_review("ALTER TABLE t " + actions.join(", ")).is_complete(),
  )
  let good = "x".repeat(63)
  assert_true(
    column_review("ALTER TABLE t ADD \"" + good + "\" int, ADD b int").is_complete(),
  )
  assert_false(
    column_review("ALTER TABLE t ADD \"" + good + "x\" int, ADD b int").is_complete(),
  )
  assert_true(
    column_review(
      "ALTER TABLE t ADD a int DEFAULT " +
      "(".repeat(32) +
      "1" +
      ")".repeat(32) +
      ", ADD b int",
    ).is_complete(),
  )
  assert_false(
    column_review(
      "ALTER TABLE t ADD a int DEFAULT " +
      "(".repeat(33) +
      "1" +
      ")".repeat(33) +
      ", ADD b int",
    ).is_complete(),
  )
}

///|
test "combined additions retain and release locks at savepoint boundaries" {
  let kept = column_review(
    "BEGIN; SAVEPOINT s; ALTER TABLE orders ADD a int, ADD b int; UPDATE orders SET amount=1 WHERE id=1; ROLLBACK TO s; UPDATE orders SET amount=1 WHERE id=1; COMMIT;",
  )
  assert_true(kept.is_complete())
  let held = kept.findings().filter(f => f.code == "PG803")
  assert_eq(held.length(), 1)
  assert_eq(held[0].statement, 4)
  let unknown = column_review(
    "BEGIN; ALTER TABLE orders ADD a int, DROP COLUMN b; COMMIT; BEGIN; ALTER TABLE orders ADD c int, ADD d int; COMMIT;",
  )
  assert_false(unknown.is_complete())
  assert_eq(unknown.statements()[4].operation, "add_columns")
  assert_eq(unknown.findings().filter(f => f.code == "PG501").length(), 1)
}

///|
test "combined addition prefixes replay deterministically without certifying partial input" {
  let sql = "ALTER TABLE t ADD a numeric(12,2) DEFAULT 0, ADD b text DEFAULT 'a,b' NOT NULL;"
  for end in 0..<=sql.length() {
    let text = sql[:end].to_owned()
    let r = column_review(text)
    assert_eq(@moonddl_guard.decode_report(r.to_json().stringify()), r)
    assert_eq(r.to_json(), column_review(text).to_json())
    if text.has_suffix(",") || text.has_suffix(" ADD") {
      assert_false(r.is_complete())
    }
  }
  let old = column_review("ALTER TABLE t ADD a int, ADD b text")
  let current = column_review("ALTER TABLE t ADD a int, ADD b text NOT NULL")
  let delta = @moonddl_guard.compare_reviews(old, current)
  assert_eq(delta.exit_code(), 1)
  assert_eq(
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
    delta.to_json(),
  )
}
