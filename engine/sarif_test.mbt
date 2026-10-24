///|
fn export_run(review : @moonddl_guard.Review, path : String) -> Json raise {
  let report = review.to_sarif(path)
  assert_eq(report, @json.parse(report.stringify()))
  guard report is { "version": String("2.1.0"), "runs": Array(runs), .. } else {
    fail("Missing SARIF run")
  }
  assert_eq(runs.length(), 1)
  runs[0]
}

///|
test "SARIF preserves complete review severity actions and UTF16 coordinates" {
  let sql = "-- 😀\r\nBEGIN; CREATE INDEX CONCURRENTLY x ON t(a); COMMIT;"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  let run = export_run(r, "migrations/订单 #1%.sql")
  guard run
    is {
      "columnKind": String("utf16CodeUnits"),
      "results": Array(results),
      "artifacts": Array(artifacts),
      "properties": { "moonddlReview": original, .. },
      "tool": { "driver": { "rules": Array(rules), .. }, .. },
      ..
    } else {
    fail("Incomplete SARIF data")
  }
  assert_eq(original, r.to_json())
  assert_eq(results.length(), r.findings().length())
  guard artifacts[0]
    is {
      "location": { "uri": String(uri), .. },
      "contents": { "text": String(source), .. },
      ..
    } else {
    fail("Missing source")
  }
  assert_eq(uri, "migrations/%E8%AE%A2%E5%8D%95%20%231%25.sql")
  assert_eq(source, sql)
  for i in 0..<results.length() {
    let f = r.findings()[i]
    guard results[i]
      is {
        "ruleId": String(code),
        "level": String(level),
        "message": { "text": String(message), .. },
        "locations": Array(locations),
        ..
      } else {
      fail("Missing result")
    }
    assert_eq(code, f.code)
    assert_eq(
      level,
      if f.severity == @moonddl_guard.Error {
        "error"
      } else {
        "note"
      },
    )
    assert_true(message.contains(f.action))
    assert_true(
      rules.any(rule => rule is { "id": String(id), .. } && id == code),
    )
    guard locations[0] is { "physicalLocation": { "region": region, .. }, .. } else {
      fail("Missing region")
    }
    assert_eq(
      region,
      Json({
        "startLine": f.location.line,
        "startColumn": f.location.column,
        "charOffset": f.location.start,
        "charLength": f.location.end - f.location.start,
      }),
    )
  }
}

///|
test "SARIF incomplete empty and warning reports retain execution outcome" {
  for sql in ["SELECT 1", "/*", "", "DROP INDEX x"] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    let run = export_run(r, "migrations\\change.sql")
    guard run
      is { "invocations": Array(invocations), "results": Array(results), .. } else {
      fail("Missing execution metadata")
    }
    assert_eq(invocations[0], Json({ "executionSuccessful": r.is_complete() }))
    assert_eq(results.length(), r.findings().length())
    if sql == "DROP INDEX x" {
      assert_true(
        results.any(result => result is { "level": String("warning"), .. }),
      )
    }
  }
}

///|
test "SARIF paths reject ambiguity before exporting and calls recover" {
  let r = @moonddl_guard.review_sql(
    "",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  for
    path in [
      "", "/root/file.sql", "C:\\a.sql", "../a.sql", "a/../b", "./a.sql", "a//b",
      "a/", "https://host/file", "a\n.sql",
    ] {
    try r.to_sarif(path) catch {
      @moonddl_guard.InvalidArtifactPath(_) => ()
    } noraise {
      _ => fail("Path should fail: " + path)
    }
  }
  assert_eq(r.to_sarif("m/a.sql"), r.to_sarif("m\\a.sql"))
  assert_eq(r.to_sarif("a.sql"), r.to_sarif("a.sql"))
  let broken = "😀"[0:1].to_owned()
  try r.to_sarif(broken) catch {
    @moonddl_guard.InvalidArtifactPath(_) => ()
  } noraise {
    _ => fail("Invalid UTF-16 path must not be replaced silently")
  }
}
