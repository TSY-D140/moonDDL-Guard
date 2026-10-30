///|
fn rename_review(sql : String) -> @moonddl_guard.Review {
  @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
}

///|
test "rename reviews table column constraint and index without claiming a rewrite" {
  for
    (sql, operation) in [
      ("ALTER TABLE public.orders RENAME TO purchases", "rename_table"),
      ("ALTER TABLE ONLY orders RENAME COLUMN old TO new", "rename_column"),
      ("ALTER TABLE IF EXISTS orders RENAME old TO new", "rename_column"),
      (
        "ALTER TABLE orders RENAME CONSTRAINT old_fk TO new_fk", "rename_constraint",
      ),
      ("ALTER INDEX IF EXISTS public.old_idx RENAME TO new_idx", "rename_index"),
      (
        "ALTER TABLE \"订;单😀\" RENAME COLUMN \"旧名\" TO \"新名\"", "rename_column",
      ),
    ] {
    let r = rename_review(sql)
    assert_true(r.is_complete(), msg=sql)
    assert_eq(r.exit_code(), 1)
    assert_eq(r.statements()[0].operation, operation)
    assert_eq(r.findings().filter(f => f.code == "PG702").length(), 1)
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
}

///|
test "rename moves lexical table locks and savepoint rollback restores old identities" {
  let r = rename_review(
    "BEGIN; ALTER TABLE public.old RENAME TO fresh; ALTER TABLE public.fresh VALIDATE CONSTRAINT c; COMMIT;",
  )
  assert_eq(r.findings().filter(f => f.code == "PG405").length(), 1)
  let rollback = rename_review(
    "BEGIN; ALTER TABLE public.old ALTER a SET NOT NULL; SAVEPOINT p; ALTER TABLE public.old RENAME TO fresh; ROLLBACK TO p; ALTER TABLE public.old VALIDATE CONSTRAINT c; ALTER TABLE public.fresh VALIDATE CONSTRAINT c; COMMIT;",
  )
  assert_eq(rollback.findings().filter(f => f.code == "PG405").length(), 1)
  assert_eq(rollback.findings().filter(f => f.code == "PG405")[0].statement, 6)
  let released = rename_review(
    "BEGIN; SAVEPOINT p; ALTER TABLE \"a.b\" RENAME TO \"x.y\"; RELEASE p; ALTER TABLE \"x.y\" VALIDATE CONSTRAINT c; COMMIT;",
  )
  assert_eq(released.findings().filter(f => f.code == "PG405").length(), 1)
}

///|
test "rename malformed clauses and unsupported object kinds remain retained" {
  for
    sql in [
      "ALTER TABLE t RENAME TO", "ALTER TABLE t RENAME COLUMN a TO", "ALTER TABLE t RENAME TO public.x",
      "ALTER TABLE t RENAME COLUMN a TO b, DROP COLUMN c", "ALTER TABLE t RENAME COLUMN \"\" TO b",
      "ALTER TABLE ONLY t RENAME TO x", "ALTER INDEX x RENAME COLUMN a TO b", "ALTER TYPE t RENAME TO u",
    ] {
    let r = rename_review(sql)
    assert_false(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].sql, sql)
  }
}

///|
test "rename composes with budgets baseline gates and deterministic export" {
  let r = rename_review("SET lock_timeout='100ms'; ALTER TABLE t RENAME TO n;")
  assert_eq(r.findings().filter(f => f.code == "PG305").length(), 1)
  let delta = @moonddl_guard.compare_reviews(rename_review(""), r)
  assert_eq(delta.exit_code(), 1)
  assert_eq(
    delta.to_json(),
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
  )
  assert_eq(
    r.to_sarif("migrations/rename.sql"),
    r.to_sarif("migrations/rename.sql"),
  )
}
