///|
test "report round trips preserve SQL findings incomplete status and Unicode" {
  for
    sql in [
      "", "-- 😀\r\nCREATE INDEX \"a;b\" ON t (c);", "DO $$ BEGIN RAISE NOTICE 'x;'; END $$;",
      "CREATE INDEX x ON t (a", "BEGIN;CREATE INDEX CONCURRENTLY x ON t (a);ROLLBACK;",
    ] {
    for
      transaction in [
        @moonddl_guard.Autocommit,
        @moonddl_guard.Active,
        @moonddl_guard.UnknownTransaction,
      ] {
      for
        delivery in [
          @moonddl_guard.PerStatement,
          @moonddl_guard.SimpleQuery,
          @moonddl_guard.UnknownDelivery,
        ] {
        let first = @moonddl_guard.review_sql(sql, transaction~, delivery~)
        let second = @moonddl_guard.decode_report(
          first.to_json().stringify(indent=2),
        )
        assert_eq(first.to_json(), second.to_json())
        assert_eq(first.exit_code(), second.exit_code())
      }
    }
  }
}

///|
test "unknown altered missing and duplicate fields are rejected" {
  let valid = @moonddl_guard.review_sql(
      "CREATE INDEX x ON t (a);",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    .to_json()
    .stringify()
  let mutations = [
    "{\"extra\":1," + valid[1:].to_owned(),
    "{\"source\":\"\"," + valid[1:].to_owned(),
    "{\"sour\\u0063e\":\"\"," + valid[1:].to_owned(),
    "{}",
    "[]",
    "{",
    "{\"format\":\"moonddl.review.v99\"}",
  ]
  for text in mutations {
    try @moonddl_guard.decode_report(text) catch {
      @moonddl_guard.InvalidReport(_) => ()
    } noraise {
      _ => fail("invalid report accepted")
    }
  }
  let document = @json.parse(valid)
  match document {
    Object(fields) => {
      fields["findings"] = []
      try @moonddl_guard.decode_report(document.stringify()) catch {
        @moonddl_guard.InvalidReport(_) => ()
      } noraise {
        _ => fail("omitted diagnostics accepted")
      }
    }
    _ => fail("expected report object")
  }
}

///|
test "report object order is irrelevant and nested unknown data is rejected" {
  let review = @moonddl_guard.review_sql(
    "CREATE INDEX x ON t (a);",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  let document = review.to_json()
  match document {
    Object(fields) => {
      let reordered : Map[String, Json] = Map([])
      for
        key in [
          "findings", "statements", "exit_code", "complete", "delivery", "transaction",
          "source", "postgres", "format",
        ] {
        reordered[key] = fields[key]
      }
      assert_eq(
        @moonddl_guard.decode_report(Json::object(reordered).stringify()).to_json(),
        document,
      )
      match fields["findings"] {
        Array(findings) =>
          match findings[0] {
            Object(finding) => finding["unrecognized"] = true
            _ => fail("expected finding object")
          }
        _ => fail("expected findings")
      }
      try @moonddl_guard.decode_report(document.stringify()) catch {
        @moonddl_guard.InvalidReport(_) => ()
      } noraise {
        _ => fail("nested field was discarded")
      }
    }
    _ => fail("expected report")
  }
}

///|
test "limits boundaries and recovery remain deterministic" {
  let statement = "CREATE INDEX x ON t (a);"
  let build = StringBuilder()
  for _ in 0..<512 {
    build.write_string(statement)
  }
  let exact = @moonddl_guard.review_sql(
    build.to_string(),
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(exact.is_complete())
  build.write_string(statement)
  let over = @moonddl_guard.review_sql(
    build.to_string(),
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_false(over.is_complete())
  assert_eq(over.findings()[0].code, "PG000")
  assert_eq(
    @moonddl_guard.decode_report(over.to_json().stringify()).to_json(),
    over.to_json(),
  )
}

///|
test "source limit accepts boundary and rejects overflow without truncation" {
  let build = StringBuilder()
  for _ in 0..<262144 {
    build.write_char(' ')
  }
  let r = @moonddl_guard.review_sql(
    build.to_string(),
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  build.write_char(' ')
  let over = @moonddl_guard.review_sql(
    build.to_string(),
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_false(over.is_complete())
  assert_eq(
    over.to_json(),
    @moonddl_guard.decode_report(over.to_json().stringify()).to_json(),
  )
}

///|
test "nested comments strings and unsupported suffixes preserve all statements" {
  let sql = "/* outer /* inner ; */ still ; */ CREATE INDEX \"x;😀\" ON t (a); SELECT 'COMMIT;'; CREATE INDEX y ON t (a) INCLUDE (b); CREATE INDEX z ON t (a);"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_eq(r.statements().length(), 4)
  assert_eq(r.statements()[0].coverage, @moonddl_guard.Analyzed)
  assert_eq(r.statements()[1].coverage, @moonddl_guard.Unsupported)
  assert_eq(r.statements()[2].coverage, @moonddl_guard.Unsupported)
  assert_eq(r.statements()[3].coverage, @moonddl_guard.Analyzed)
  assert_false(r.is_complete())
}
