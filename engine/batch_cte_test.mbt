///|
test "bounded read CTE supports update and delete without claiming target cardinality" {
  for
    suffix in [
      "UPDATE orders o SET status='new' FROM batch b WHERE o.id=b.id", "DELETE FROM orders o USING batch b WHERE o.id=b.id",
    ] {
    for lock in ["", "FOR UPDATE", "FOR UPDATE SKIP LOCKED", "FOR SHARE NOWAIT"] {
      let r = @moonddl_guard.review_sql(
        "WITH batch AS (SELECT id FROM orders WHERE status='old' ORDER BY id LIMIT 100 " +
        lock +
        ") " +
        suffix,
        transaction=@moonddl_guard.Autocommit,
        delivery=@moonddl_guard.PerStatement,
      )
      assert_true(r.is_complete(), msg=lock)
      assert_eq(r.findings().filter(f => f.code == "PG811").length(), 1)
      assert_eq(r.exit_code(), 1)
      assert_eq(
        r.to_json(),
        @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
      )
    }
  }
}

///|
test "write recursive unbounded and unassessed CTE expressions stay incomplete" {
  for
    cte in [
      "batch AS (DELETE FROM orders RETURNING id)", "batch AS (SELECT id FROM orders)",
      "batch AS (SELECT id FROM orders LIMIT 100001)", "batch AS (SELECT id FROM orders LIMIT 1 OFFSET 10)",
      "batch AS (SELECT custom(id) FROM orders LIMIT 1)", "batch AS (SELECT id FROM orders LIMIT 1), extra AS (SELECT 1)",
    ] {
    let sql = "WITH " +
      cte +
      " UPDATE orders o SET status='new' FROM batch b WHERE o.id=b.id"
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete(), msg=cte)
    assert_eq(r.statements()[0].sql, sql)
  }
}
