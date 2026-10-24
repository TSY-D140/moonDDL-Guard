///|
fn codes(
  sql : String,
  transaction : @moonddl_guard.Transaction,
  delivery : @moonddl_guard.Delivery,
) -> Array[String] {
  @moonddl_guard.review_sql(sql, transaction~, delivery~)
  .findings()
  .map(f => f.code)
}

///|
test "quoted words must never become transaction controls" {
  for quoted in ["'COMMIT';", "\"COMMIT\";", "$$COMMIT$$;", "E'COMMIT';"] {
    let r = @moonddl_guard.review_sql(
      quoted + "CREATE INDEX CONCURRENTLY x ON t (a);",
      transaction=@moonddl_guard.Active,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete())
    assert_eq(r.exit_code(), 2)
    assert_eq(r.statements()[0].coverage, @moonddl_guard.Unsupported)
  }
}

///|
test "concurrent index requires known autocommit and delivery" {
  let sql = "CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS x ON t (a);"
  let ok = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(ok.is_complete())
  assert_eq(ok.exit_code(), 0)
  assert_eq(ok.findings().map(f => f.code), ["PG105", "PG103", "PG104"])
  for
    (transaction, delivery) in [
      (@moonddl_guard.UnknownTransaction, @moonddl_guard.PerStatement),
      (@moonddl_guard.Autocommit, @moonddl_guard.UnknownDelivery),
    ] {
    let r = @moonddl_guard.review_sql(sql, transaction~, delivery~)
    assert_false(r.is_complete())
    assert_eq(r.exit_code(), 2)
    assert_eq(r.findings()[0].code, "PG202")
  }
  assert_true(
    codes(sql, @moonddl_guard.Active, @moonddl_guard.PerStatement).contains(
      "PG201",
    ),
  )
}

///|
test "batch grouping differs from separate queries" {
  let index = "CREATE INDEX CONCURRENTLY x ON t (a);"
  assert_false(
    codes(index + index, @moonddl_guard.Autocommit, @moonddl_guard.PerStatement).contains(
      "PG201",
    ),
  )
  assert_true(
    codes(index + index, @moonddl_guard.Autocommit, @moonddl_guard.SimpleQuery).contains(
      "PG201",
    ),
  )
  assert_false(
    codes(
      index + "; -- trivia only",
      @moonddl_guard.Autocommit,
      @moonddl_guard.SimpleQuery,
    ).contains("PG201"),
  )
}

///|
test "explicit transaction rollback recovers known state" {
  let sql = "BEGIN; CREATE INDEX CONCURRENTLY x ON t (a); ROLLBACK; CREATE INDEX CONCURRENTLY y ON t (a);"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(r.findings().filter(f => f.code == "PG201").length(), 1)
  assert_eq(r.statements().length(), 4)
  assert_true(r.is_complete())
  let batch = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.SimpleQuery,
  )
  assert_eq(batch.findings().filter(f => f.code == "PG201").length(), 2)
}

///|
test "aliases chain inherited transactions and dangling begin" {
  let index = "CREATE INDEX CONCURRENTLY x ON t (a);"
  for
    begin in [
      "BEGIN;", "BEGIN WORK;", "BEGIN TRANSACTION;", "START TRANSACTION;",
    ] {
    assert_true(
      codes(
        begin + index + "END;",
        @moonddl_guard.Autocommit,
        @moonddl_guard.PerStatement,
      ).contains("PG201"),
    )
  }
  for end in ["COMMIT AND CHAIN;", "ROLLBACK AND CHAIN;"] {
    assert_true(
      codes(
        "BEGIN;" + end + index,
        @moonddl_guard.Autocommit,
        @moonddl_guard.PerStatement,
      ).contains("PG201"),
    )
  }
  for end in ["COMMIT;", "END;", "ROLLBACK;", "ABORT;", "COMMIT AND NO CHAIN;"] {
    assert_false(
      codes(end + index, @moonddl_guard.Active, @moonddl_guard.PerStatement).contains(
        "PG201",
      ),
    )
  }
  assert_false(
    codes("", @moonddl_guard.Active, @moonddl_guard.PerStatement).contains(
      "PG204",
    ),
  )
  assert_true(
    codes("BEGIN;", @moonddl_guard.Autocommit, @moonddl_guard.PerStatement).contains(
      "PG204",
    ),
  )
  assert_true(
    codes(
      "BEGIN;BEGIN;COMMIT;",
      @moonddl_guard.Autocommit,
      @moonddl_guard.PerStatement,
    ).contains("PG203"),
  )
}

///|
test "unknown statements poison state without losing later diagnostics" {
  let sql = "ROLLBACK TO SAVEPOINT x; CREATE INDEX CONCURRENTLY x ON t (a); COMMIT; CREATE INDEX CONCURRENTLY y ON t (a);"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Active,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_false(r.is_complete())
  assert_eq(r.exit_code(), 2)
  assert_eq(r.findings().filter(f => f.code == "PG202").length(), 1)
  assert_eq(r.statements()[3].coverage, @moonddl_guard.Analyzed)
  assert_false(
    @moonddl_guard.review_sql(
      "BEGIN ISOLATION LEVEL SERIALIZABLE;",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
}
