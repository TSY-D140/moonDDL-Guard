///|
fn delta_review(sql : String) -> @moonddl_guard.Review {
  @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
}

///|
test "baseline gates introduced risks and retains complete current findings" {
  let before = delta_review("CREATE INDEX x ON t(a);")
  let same = @moonddl_guard.compare_reviews(
    before,
    delta_review("-- moved 😀\r\nCREATE INDEX x ON t(a);"),
  )
  assert_eq(before.exit_code(), 1)
  assert_eq(same.exit_code(), 0)
  assert_eq(same.unchanged_count(), 1)
  assert_eq(same.introduced().length(), 0)
  let after = delta_review("CREATE INDEX x ON t(a); DROP INDEX old_idx;")
  let delta = @moonddl_guard.compare_reviews(before, after)
  assert_eq(delta.exit_code(), 1)
  assert_eq(delta.introduced().map(f => f.code), ["PG109", "PG110"])
  assert_eq(delta.unchanged_count(), 1)
  assert_eq(
    delta.to_json(),
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
  )
  assert_true(delta.to_text().contains("Full current review"))
  delta.introduced().clear()
  assert_eq(delta.introduced().length(), 2)
}

///|
test "matching is FIFO multiset preserving duplicate occurrences and conservation" {
  let sql = "CREATE INDEX x ON t(a);"
  for (old_count, new_count) in [(2, 1), (1, 2), (2, 2), (0, 2), (2, 0)] {
    let old = StringBuilder()
    let new = StringBuilder()
    for _ in 0..<old_count {
      old.write_string(sql)
    }
    for _ in 0..<new_count {
      new.write_string(sql)
    }
    let before = delta_review(old.to_string())
    let after = delta_review(new.to_string())
    let delta = @moonddl_guard.compare_reviews(before, after)
    assert_eq(
      before.findings().length(),
      delta.resolved().length() + delta.unchanged_count(),
    )
    assert_eq(
      after.findings().length(),
      delta.introduced().length() + delta.unchanged_count(),
    )
    if old_count == 2 && new_count == 1 {
      assert_eq(delta.resolved()[0].statement, 2)
    }
    assert_eq(
      delta.to_json(),
      @moonddl_guard.compare_reviews(before, after).to_json(),
    )
  }
}

///|
test "changed SQL budgets and diagnostic semantics do not inherit baseline approval" {
  let before = delta_review("SET lock_timeout='1s'; CREATE INDEX x ON t(a);")
  let after = delta_review("SET lock_timeout='2s'; CREATE INDEX x ON t(a);")
  let delta = @moonddl_guard.compare_reviews(before, after)
  assert_eq(delta.introduced().map(f => f.code), ["PG305"])
  assert_eq(delta.resolved().map(f => f.code), ["PG305"])
  assert_eq(delta.exit_code(), 0)
  let changed = @moonddl_guard.compare_reviews(
    delta_review("CREATE INDEX x ON t(a);"),
    delta_review("CREATE INDEX x ON t (a);"),
  )
  assert_eq(changed.introduced().length(), 1)
  assert_eq(changed.resolved().length(), 1)
  assert_eq(changed.exit_code(), 1)
}

///|
test "incomplete current report cannot pass and invalid baselines are rejected" {
  let before = delta_review("CREATE INDEX x ON t(a);")
  let invalid = delta_review("CREATE INDEX x ON t(a); SELECT 1;")
  let delta = @moonddl_guard.compare_reviews(before, invalid)
  assert_eq(delta.exit_code(), 2)
  assert_eq(
    delta.to_json(),
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
  )
  let other = @moonddl_guard.review_sql(
    "CREATE INDEX x ON t(a);",
    transaction=@moonddl_guard.Active,
    delivery=@moonddl_guard.PerStatement,
  )
  for (baseline, current) in [(invalid, before), (before, other)] {
    try @moonddl_guard.compare_reviews(baseline, current) catch {
      @moonddl_guard.IncompatibleBaseline(_) => ()
    } noraise {
      _ => fail("Incompatible baseline must fail")
    }
  }
}

///|
test "delta decoder rejects tampering unknown nested data and duplicate keys" {
  let delta = @moonddl_guard.compare_reviews(
    delta_review(""),
    delta_review("DROP INDEX x;"),
  )
  let value = delta.to_json()
  guard value is Object(fields) else { fail("Expected object") }
  for key in ["future", "unchanged", "introduced"] {
    let changed = fields.copy()
    changed[key] = Json(999)
    try @moonddl_guard.decode_delta(Json(changed).stringify()) catch {
      @moonddl_guard.InvalidReport(_) => ()
    } noraise {
      _ => fail("Edited delta must fail")
    }
  }
  guard fields.get("baseline") is Some(Object(nested)) else {
    fail("Missing baseline")
  }
  let altered_baseline = nested.copy()
  altered_baseline["future"] = Json(true)
  let altered = fields.copy()
  altered["baseline"] = Json(altered_baseline)
  try @moonddl_guard.decode_delta(Json(altered).stringify()) catch {
    @moonddl_guard.InvalidReport(_) => ()
  } noraise {
    _ => fail("Unknown nested report data must not be dropped")
  }
  for
    text in [
      "{}", "{", "{\"format\":\"moonddl.delta.v1\",\"format\":\"moonddl.delta.v1\"}",
    ] {
    try @moonddl_guard.decode_delta(text) catch {
      @moonddl_guard.InvalidReport(_) => ()
    } noraise {
      _ => fail("Malformed delta must fail")
    }
  }
}
