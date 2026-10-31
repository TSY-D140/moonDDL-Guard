///|
fn main raise {
  let baseline = @guard.review_sql(
    "ALTER TABLE orders ADD doubled int GENERATED ALWAYS AS (amount*2) VIRTUAL;",
    transaction=@guard.Autocommit,
    delivery=@guard.PerStatement,
  )
  let current = @guard.review_sql(
    "ALTER TABLE orders ADD doubled int GENERATED ALWAYS AS (amount*2) VIRTUAL NOT NULL;",
    transaction=@guard.Autocommit,
    delivery=@guard.PerStatement,
  )
  assert_true(current.is_complete())
  assert_eq(current.findings().filter(f => f.code == "PG520").length(), 1)
  assert_eq(@guard.decode_report(current.to_json().stringify()), current)
  let delta = @guard.compare_reviews(baseline, current)
  assert_eq(delta.exit_code(), 1)
  let files = @guard.review_isolated_files(
    [{ path: "001.sql", sql: "ALTER TABLE orders ADD a int;", }],
    transaction=@guard.Autocommit,
    delivery=@guard.PerStatement,
  )
  assert_eq(
    @guard.decode_batch(files.to_json().stringify()).to_json(),
    files.to_json(),
  )
  let unchanged = @guard.compare_batches(files, files)
  assert_eq(unchanged.exit_code(), 0)
  assert_eq(
    @guard.decode_batch_delta(unchanged.to_json().stringify()).to_json(),
    unchanged.to_json(),
  )
  assert_eq(
    @guard.decode_file_order(
      "{\"format\":\"moonddl.order.v1\",\"files\":[\"001.sql\"]}",
    ),
    ["001.sql"],
  )
  println("Independent consumer: report replay and new-risk gate passed.")
}
