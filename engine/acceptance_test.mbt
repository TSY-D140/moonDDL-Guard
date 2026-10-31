///|
test "generated NOT NULL survives parsing and reports validation independently of rewriting" {
  for storage in ["VIRTUAL", "STORED", ""] {
    let r = @moonddl_guard.review_sql(
      "ALTER TABLE orders ADD doubled int GENERATED ALWAYS AS (amount*2) " +
      storage +
      " NOT NULL",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete())
    assert_eq(r.findings().filter(f => f.code == "PG520").length(), 1)
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
  let r = @moonddl_guard.review_sql(
    "ALTER TABLE orders ADD doubled int GENERATED ALWAYS AS (amount*2) VIRTUAL",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(r.findings().filter(f => f.code == "PG520").length(), 0)
}
