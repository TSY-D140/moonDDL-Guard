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
  println("Independent consumer: report replay and new-risk gate passed.")
}
