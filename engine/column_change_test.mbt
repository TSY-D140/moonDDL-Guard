///|
fn column_review(sql : String) -> @moonddl_guard.Review {
  @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
}

///|
test "column additions separate default evaluation rewrite and validation" {
  for
    (tail, codes) in [
      ("a int", ["PG501", "PG502", "PG507"]),
      ("a integer DEFAULT 0 NOT NULL", ["PG501", "PG502", "PG506", "PG507"]),
      ("a text DEFAULT 'hello'", ["PG501", "PG502", "PG507"]),
      ("a boolean DEFAULT false", ["PG501", "PG502", "PG507"]),
      (
        "a timestamp with time zone DEFAULT now()",
        ["PG501", "PG502", "PG505", "PG507"],
      ),
      (
        "a timestamptz DEFAULT CURRENT_TIMESTAMP",
        ["PG501", "PG502", "PG505", "PG507"],
      ),
      ("a timestamptz DEFAULT clock_timestamp()", ["PG501", "PG503", "PG507"]),
      ("a double precision DEFAULT random()", ["PG501", "PG503", "PG507"]),
      ("a bigint DEFAULT nextval('order_seq')", ["PG501", "PG503", "PG507"]),
      ("a public.positive_amount", ["PG501", "PG504", "PG507"]),
      ("a \"text\" DEFAULT 'x'", ["PG501", "PG504", "PG507"]),
    ] {
    let r = column_review("ALTER TABLE orders ADD COLUMN " + tail)
    assert_true(r.is_complete(), msg=tail)
    assert_eq(r.findings().map(f => f.code), codes, msg=tail)
  }
}

///|
test "column types accept bounded typemods and reject unknown trailing syntax" {
  for
    tail in [
      "a numeric(12,2) DEFAULT -1", "a numeric(3,-2) DEFAULT 0", "a varchar(255) DEFAULT ''",
      "a character varying(50)", "a timestamp(6) without time zone", "a time(0) with time zone",
      "IF NOT EXISTS a int DEFAULT (42)", "\"备注😀\" text NOT NULL",
    ] {
    assert_true(
      column_review("ALTER TABLE ONLY orders ADD " + tail).is_complete(),
      msg=tail,
    )
  }
  for
    tail in [
      "a numeric(0,2)", "a numeric(1001)", "a numeric(10,1001)", "a timestamp(7)",
      "a int(2)", "a varchar(0)", "a int[]", "a int GENERATED ALWAYS AS IDENTITY (CYCLE)",
      "a int DEFAULT custom()", "a int DEFAULT (SELECT 1)", "a int DEFAULT 1 + 2",
      "a text COLLATE \"C\"", "a int DEFAULT 0, ADD COLUMN b int", "\"\" int", "a int DEFAULT",
    ] {
    let sql = "ALTER TABLE t ADD COLUMN " + tail + ";"
    let r = column_review(sql)
    assert_false(r.is_complete(), msg=tail)
    assert_eq(r.statements()[0].sql, sql)
    assert_eq(r.exit_code(), 2)
  }
}

///|
test "type conversions preserve USING distinction without fabricating old type evidence" {
  for
    tail in [
      "TYPE bigint", "SET DATA TYPE numeric(12,2)", "TYPE numeric(12,2) USING amount::numeric(12,2)",
      "TYPE bigint USING (amount * 100)", "TYPE public.amount_type USING amount",
    ] {
    let r = column_review("ALTER TABLE orders ALTER COLUMN amount " + tail)
    assert_true(r.is_complete(), msg=tail)
    assert_eq(r.findings().map(f => f.code), [
      "PG501", "PG509", "PG510", "PG511",
    ])
    assert_eq(r.statements()[0].operation, "alter_column_type")
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
  for
    tail in [
      "TYPE", "TYPE numeric(12,2) USING", "TYPE bigint USING custom(amount)", "TYPE bigint USING (SELECT 1)",
      "TYPE int, DROP COLUMN b", "TYPE int COLLATE x", "TYPE int[]",
    ] {
    assert_false(
      column_review("ALTER TABLE t ALTER a " + tail).is_complete(),
      msg=tail,
    )
  }
}

///|
test "changing future defaults is not a backfill or volatile table rewrite" {
  for
    tail in [
      "SET DEFAULT NULL", "SET DEFAULT 0", "SET DEFAULT clock_timestamp()", "DROP DEFAULT",
    ] {
    let r = column_review("ALTER TABLE orders ALTER created_at " + tail)
    assert_true(r.is_complete(), msg=tail)
    assert_eq(r.findings().map(f => f.code), ["PG501", "PG512"])
  }
}

///|
test "column operations retain and restore strong locks and timeout scope" {
  let r = column_review(
    "SET lock_timeout='250ms'; BEGIN; SAVEPOINT p; ALTER TABLE t ADD COLUMN a int; ROLLBACK TO p; ALTER TABLE t VALIDATE CONSTRAINT c; ALTER TABLE t ALTER COLUMN b TYPE bigint; ALTER TABLE t VALIDATE CONSTRAINT c; COMMIT;",
  )
  assert_true(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG405").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG305").length(), 4)
  let recovery = column_review(
    "ALTER TABLE t ADD COLUMN a int[]; ROLLBACK; ALTER TABLE t ADD COLUMN b int;",
  )
  assert_false(recovery.is_complete())
  assert_eq(recovery.statements()[2].operation, "add_column")
}

///|
test "new column risks are deterministic and cannot be hidden by baseline replay" {
  let sql = "-- 😀\r\nALTER TABLE orders ADD COLUMN stamp timestamptz DEFAULT clock_timestamp();"
  let r = column_review(sql)
  assert_eq(r.to_json(), column_review(sql).to_json())
  let delta = @moonddl_guard.compare_reviews(column_review(""), r)
  assert_eq(delta.exit_code(), 1)
  assert_eq(
    delta.to_json(),
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
  )
  let sarif = r.to_sarif("migrations/columns.sql")
  assert_eq(sarif, @json.parse(sarif.stringify()))
  let same = @moonddl_guard.compare_reviews(r, column_review("\n" + sql))
  assert_eq(same.introduced().length(), 0)
}
