///|
fn budget_review(
  sql : String,
  transaction~ : @moonddl_guard.Transaction = @moonddl_guard.Autocommit,
  delivery~ : @moonddl_guard.Delivery = @moonddl_guard.PerStatement,
) -> @moonddl_guard.Review {
  @moonddl_guard.review_sql(sql, transaction~, delivery~)
}

///|
fn lock_values(review : @moonddl_guard.Review) -> Array[String] {
  review.findings().filter(f => f.code == "PG305").map(f => f.message)
}

///|
test "timeout decimal units boundaries and replay" {
  for
    (value, ms) in [
      ("0", "0"),
      ("1", "1"),
      ("2147483647ms", "2147483647"),
      ("2147483.647s", "2147483647"),
      ("24d", "2073600000"),
      (".5s", "500"),
      ("0.001s", "1"),
      ("1.5min", "90000"),
      (".5h", "1800000"),
      ("1.5d", "129600000"),
      (" 2 s ", "2000"),
      ("1.000000ms", "1"),
    ] {
    let sql = "SET SESSION lock_timeout TO '" +
      value +
      "'; CREATE INDEX CONCURRENTLY x ON t (a);"
    let r = budget_review(sql)
    assert_true(r.is_complete(), msg=value)
    if ms == "0" {
      assert_eq(r.findings().filter(f => f.code == "PG301").length(), 1)
      assert_eq(r.exit_code(), 1)
    } else {
      assert_eq(lock_values(r), [
        "Effective lock_timeout is " + ms + "ms for this index.",
      ])
      assert_eq(r.exit_code(), 0)
    }
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
    assert_eq(r.to_json(), budget_review(sql).to_json())
  }
  let r = budget_review(
    "set lock_timeout = 123; CREATE INDEX CONCURRENTLY x ON t(a);",
  )
  assert_eq(lock_values(r), ["Effective lock_timeout is 123ms for this index."])
}

///|
test "ambiguous rounding overflow malformed and unassessed SET never pass" {
  for
    value in [
      "2147483648", "2147483.648s", "999999999999999999999999", "-1", ".5ms", "0.0001min",
      "0.0001h", "0.001d", "25d", "0.000001s", "1.0000000ms", "1.", "010", "08",
      "0x10", "1e3", "1000us", "NaN", "Infinity", "1MS", "1 s x", "", "\u{a0}1ms",
    ] {
    let r = budget_review(
      "SET lock_timeout = '" + value + "'; CREATE INDEX x ON t(a);",
    )
    assert_false(r.is_complete(), msg=value)
    assert_eq(r.exit_code(), 2)
    assert_eq(
      r.findings().filter(f => f.code == "PG304").length(),
      1,
      msg=value,
    )
    assert_eq(lock_values(r).length(), 0)
    assert_eq(r.statements()[1].coverage, @moonddl_guard.Analyzed)
  }
  for
    sql in [
      "SET lock_timeout;", "SET lock_timeout = 1, 2;", "SET lock_timeout = 1 extra;",
      "SET lock_timeout TO;", "SET lock_timeout = -1;", "SET LOCAL lock_timeout = '1s' extra;",
      "SET idle_in_transaction_session_timeout = 0;", "RESET lock_timeout;", "SET \"lock_timeout\" = '1s';",
      "'SET' lock_timeout = '1s';",
    ] {
    assert_false(budget_review(sql).is_complete(), msg=sql)
  }
}

///|
test "SESSION and LOCAL commit rollback and override" {
  let r = budget_review(
    "SET lock_timeout='2s'; BEGIN; SET lock_timeout='3s'; SET LOCAL lock_timeout='1s'; CREATE INDEX a ON t(x); COMMIT; CREATE INDEX b ON t(x); BEGIN; SET lock_timeout='4s'; SET LOCAL lock_timeout='5s'; ROLLBACK; CREATE INDEX c ON t(x); BEGIN; SET LOCAL lock_timeout='6s'; SET lock_timeout='7s'; CREATE INDEX d ON t(x); COMMIT; CREATE INDEX e ON t(x);",
  )
  assert_true(r.is_complete())
  assert_eq(lock_values(r), [
    "Effective lock_timeout is 1000ms for this index.", "Effective lock_timeout is 3000ms for this index.",
    "Effective lock_timeout is 3000ms for this index.", "Effective lock_timeout is 7000ms for this index.",
    "Effective lock_timeout is 7000ms for this index.",
  ])
}

///|
test "LOCAL outside transaction is ineffective and DEFAULT remains unknown" {
  let r = budget_review(
    "SET lock_timeout='2s'; SET LOCAL lock_timeout='1s'; CREATE INDEX CONCURRENTLY x ON t(a);",
  )
  assert_true(r.is_complete())
  assert_eq(r.exit_code(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG302").length(), 1)
  assert_eq(lock_values(r), ["Effective lock_timeout is 2000ms for this index."])
  let single = budget_review(
    "SET LOCAL lock_timeout='1s';",
    delivery=@moonddl_guard.SimpleQuery,
  )
  assert_eq(single.findings().filter(f => f.code == "PG302").length(), 1)
  for end in ["COMMIT", "ROLLBACK"] {
    let expired = budget_review(
      "BEGIN; SET LOCAL lock_timeout='1s'; " +
      end +
      "; CREATE INDEX CONCURRENTLY x ON t(a);",
    )
    assert_eq(expired.findings().filter(f => f.code == "PG303").length(), 1)
    assert_eq(lock_values(expired).length(), 0)
  }
  let reset = budget_review(
    "SET lock_timeout=0; SET lock_timeout=DEFAULT; CREATE INDEX CONCURRENTLY x ON t(a);",
  )
  assert_eq(reset.findings().filter(f => f.code == "PG301").length(), 0)
  assert_eq(reset.findings().filter(f => f.code == "PG303").length(), 1)
}

///|
test "chain clears LOCAL and nested BEGIN preserves rollback snapshot" {
  let r = budget_review(
    "SET lock_timeout='2s'; BEGIN; SET lock_timeout='3s'; BEGIN; SET LOCAL lock_timeout='1s'; ROLLBACK AND CHAIN; CREATE INDEX x ON t(a); SET LOCAL lock_timeout='4s'; COMMIT AND CHAIN; CREATE INDEX y ON t(a); COMMIT;",
  )
  assert_true(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG203").length(), 1)
  assert_eq(lock_values(r), [
    "Effective lock_timeout is 2000ms for this index.", "Effective lock_timeout is 2000ms for this index.",
  ])
}

///|
test "simple query implicit scope differs from synchronized statements" {
  let sql = "SET lock_timeout='2s'; BEGIN; SET lock_timeout='3s'; ROLLBACK; CREATE INDEX x ON t(a);"
  let separate = budget_review(sql)
  assert_eq(lock_values(separate), [
    "Effective lock_timeout is 2000ms for this index.",
  ])
  let batch = budget_review(sql, delivery=@moonddl_guard.SimpleQuery)
  assert_true(batch.is_complete())
  assert_eq(lock_values(batch).length(), 0)
  assert_eq(batch.findings().filter(f => f.code == "PG303").length(), 1)
  let scoped = budget_review(
    "SET LOCAL lock_timeout='1s'; CREATE INDEX x ON t(a); COMMIT; CREATE INDEX y ON t(a);",
    delivery=@moonddl_guard.SimpleQuery,
  )
  assert_eq(lock_values(scoped), [
    "Effective lock_timeout is 1000ms for this index.",
  ])
  assert_eq(scoped.findings().filter(f => f.code == "PG302").length(), 0)
  assert_eq(scoped.findings().filter(f => f.code == "PG303").length(), 1)
}

///|
test "inherited unknown and unassessed scopes discard certainty then recover" {
  let inherited = budget_review(
    "SET LOCAL lock_timeout='1s'; CREATE INDEX x ON t(a); ROLLBACK; CREATE INDEX y ON t(a);",
    transaction=@moonddl_guard.Active,
  )
  assert_eq(lock_values(inherited), [
    "Effective lock_timeout is 1000ms for this index.",
  ])
  assert_eq(inherited.findings().filter(f => f.code == "PG303").length(), 1)
  let unknown = budget_review(
    "SET lock_timeout='2s'; SET LOCAL lock_timeout='1s'; CREATE INDEX x ON t(a);",
    transaction=@moonddl_guard.UnknownTransaction,
    delivery=@moonddl_guard.UnknownDelivery,
  )
  assert_eq(lock_values(unknown).length(), 0)
  assert_eq(unknown.findings().filter(f => f.code == "PG303").length(), 1)
  let r = budget_review(
    "SET lock_timeout='2s'; SAVEPOINT s; CREATE INDEX x ON t(a); ROLLBACK; SET lock_timeout='3s'; CREATE INDEX CONCURRENTLY y ON t(a);",
  )
  assert_false(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG303").length(), 1)
  assert_eq(lock_values(r), ["Effective lock_timeout is 3000ms for this index."])
  assert_eq(r.statements()[5].coverage, @moonddl_guard.Analyzed)
  assert_eq(
    r.to_json(),
    @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
  )
}

///|
test "statement and lock budgets independent and ordered" {
  for statement_ms in ["1000", "2000"] {
    let r = budget_review(
      "SET lock_timeout='2s'; SET statement_timeout=" +
      statement_ms +
      "; CREATE INDEX CONCURRENTLY x ON t(a);",
    )
    assert_true(r.is_complete())
    assert_eq(r.exit_code(), 1)
    assert_eq(r.findings().filter(f => f.code == "PG306").length(), 1)
    assert_eq(r.findings().filter(f => f.code == "PG307").length(), 1)
  }
  for statement_ms in ["0", "3000"] {
    let r = budget_review(
      "SET lock_timeout='2s'; SET statement_timeout=" +
      statement_ms +
      "; CREATE INDEX CONCURRENTLY x ON t(a);",
    )
    assert_eq(r.exit_code(), 0)
    assert_eq(r.findings().filter(f => f.code == "PG306").length(), 0)
    assert_eq(
      r.findings().filter(f => f.code == "PG308").length(),
      if statement_ms == "0" {
        1
      } else {
        0
      },
    )
  }
  let r = budget_review(
    "SET lock_timeout='2s'; SET statement_timeout='30s'; BEGIN; SET LOCAL statement_timeout='1s'; CREATE INDEX x ON t(a); COMMIT; CREATE INDEX y ON t(a);",
  )
  assert_eq(r.findings().filter(f => f.code == "PG306").length(), 1)
  assert_eq(r.findings().filter(f => f.code == "PG307").map(f => f.message), [
    "Effective statement_timeout is 1000ms for this index.", "Effective statement_timeout is 30000ms for this index.",
  ])
}

///|
test "duration length limit is enforced without truncation" {
  for spaces in [61, 62] {
    let value = StringBuilder()
    value.write_string("1")
    for _ in 0..<spaces {
      value.write_string(" ")
    }
    value.write_string("ms")
    let sql = "SET lock_timeout='" +
      value.to_string() +
      "'; CREATE INDEX CONCURRENTLY x ON t(a);"
    let r = budget_review(sql)
    assert_eq(r.is_complete(), spaces == 61)
    if spaces == 61 {
      assert_eq(lock_values(r), [
        "Effective lock_timeout is 1ms for this index.",
      ])
    } else {
      assert_eq(r.findings().filter(f => f.code == "PG304").length(), 1)
      assert_eq(lock_values(r).length(), 0)
    }
    assert_eq(
      r.statements()[0].sql,
      "SET lock_timeout='" + value.to_string() + "';",
    )
  }
}

///|
test "unconfigured migrations retain prior diagnostics and calls are isolated" {
  let original = budget_review("CREATE INDEX CONCURRENTLY x ON t(a);")
  assert_eq(original.findings().map(f => f.code), ["PG105"])
  ignore(
    budget_review("SET lock_timeout=0; CREATE INDEX CONCURRENTLY x ON t(a);"),
  )
  assert_eq(
    original.to_json(),
    budget_review("CREATE INDEX CONCURRENTLY x ON t(a);").to_json(),
  )
}
