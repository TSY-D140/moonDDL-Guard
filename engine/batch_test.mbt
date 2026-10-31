///|
fn batch(
  inputs : Array[@moonddl_guard.MigrationInput],
) -> @moonddl_guard.BatchReview raise {
  @moonddl_guard.review_isolated_files(
    inputs,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
}

///|
test "batch reports associate paths and independently preserve incomplete files" {
  let inputs : Array[@moonddl_guard.MigrationInput] = [
    { path: "001/订单.sql", sql: "-- 😀\r\nALTER TABLE t ADD a int;", },
    { path: "002.sql", sql: "DO $$ BEGIN NULL; END $$;", },
    { path: "003.sql", sql: "ALTER TABLE t ADD b int;", },
  ]
  let r = batch(inputs)
  assert_eq(r.exit_code(), 2)
  assert_false(r.is_complete())
  assert_eq(r.files().map(f => f.path), inputs.map(f => f.path))
  assert_true(r.files()[2].review.is_complete())
  for i in 0..<inputs.length() {
    assert_eq(
      r.files()[i].review.to_json(),
      column_review(inputs[i].sql).to_json(),
    )
  }
  assert_eq(
    @moonddl_guard.decode_batch(r.to_json().stringify()).to_json(),
    r.to_json(),
  )
  assert_eq(batch(inputs).to_json().stringify(), r.to_json().stringify())
  inputs.push({ path: "004.sql", sql: "DROP TABLE t", })
  assert_eq(r.files().length(), 3)
  let view = r.files()
  view[0].review.findings.clear()
  view[0].review.statements.clear()
  assert_true(r.files()[0].review.findings().length() > 0)
  assert_eq(r.files()[0].review.statements().length(), 1)
  ignore(view.pop())
  assert_eq(r.files().length(), 3)
  assert_true(r.to_text().contains("001/订单.sql"))
}

///|
test "batch validates complete lexical paths and case collisions" {
  for
    paths in [
      [],
      ["/a.sql"],
      ["../a.sql"],
      ["x/../a.sql"],
      ["a\\b.sql"],
      ["C:/a.sql"],
      ["a.sql", "A.sql"],
      ["a.sql", "a.sql"],
      ["x//a.sql"],
      ["a.txt"],
      ["x\n.sql"],
    ] {
    let rejected = try {
      ignore(
        batch(
          paths.map(path => @moonddl_guard.MigrationInput::{ path, sql: "", }),
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=paths.join("|"))
  }
  assert_true(batch([{ path: "sub/A.SQL", sql: "", }]).is_complete())
  let limit = Array::makei(256, i => @moonddl_guard.MigrationInput::{
    path: "f" + i.to_string() + ".sql",
    sql: "",
  })
  assert_eq(batch(limit).files().length(), 256)
  limit.push({ path: "extra.sql", sql: "", })
  assert_true(
    try {
      ignore(batch(limit))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "batch aggregate source limit rejects rather than truncates" {
  let source = " ".repeat(1048576)
  let accepted = batch([{ path: "a.sql", sql: source, }])
  assert_true(accepted.to_json().stringify().contains(source))
  assert_eq(
    @moonddl_guard.decode_batch(accepted.to_json().stringify()).to_json(),
    accepted.to_json(),
  )
  assert_true(
    try {
      ignore(
        batch([{ path: "a.sql", sql: source, }, { path: "b.sql", sql: " ", }]),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "batch replay rejects altered fields contexts paths duplicate keys and truncation" {
  let r = batch([{ path: "a.sql", sql: "ALTER TABLE t ADD a int;", }])
  let text = r.to_json().stringify()
  for
    altered in [
      "{\"extra\":true," + text[1:].to_owned(),
      "{\"format\":\"moonddl.batch.v1\"," + text[1:].to_owned(),
      text.replace_all(old="per-file-commit", new="single-transaction"),
      text.replace_all(old="a.sql", new="../a.sql"),
      text.replace_all(old="ALTER TABLE t ADD a int;", new="DROP TABLE t;"),
      text[:text.length() - 1].to_owned(),
      "{}",
    ] {
    assert_true(
      try {
        ignore(@moonddl_guard.decode_batch(altered))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "batch order plans are exact bounded ordered inventories" {
  let text = "{\"format\":\"moonddl.order.v1\",\"files\":[\"02.sql\",\"01.sql\"]}"
  assert_eq(@moonddl_guard.decode_file_order(text), ["02.sql", "01.sql"])
  for
    bad in [
      "{}",
      "{\"format\":\"moonddl.order.v1\",\"files\":[]}",
      "{\"format\":\"moonddl.order.v1\",\"files\":[\"a.sql\",\"A.sql\"]}",
      "{\"format\":\"moonddl.order.v1\",\"files\":[1]}",
      text.replace_all(old="\"files\"", new="\"extra\":0,\"files\""),
      "{\"format\":\"moonddl.order.v1\"," + text[1:].to_owned(),
    ] {
    assert_true(
      try {
        ignore(@moonddl_guard.decode_file_order(bad))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "batch baseline gates edited and appended files and rejects lost order" {
  let inputs : Array[@moonddl_guard.MigrationInput] = [
    { path: "01.sql", sql: "ALTER TABLE t ADD a int;", },
  ]
  let old = batch(inputs)
  assert_eq(@moonddl_guard.compare_batches(old, old).exit_code(), 0)
  let edited = batch([
    { path: "01.sql", sql: "ALTER TABLE t ADD a int NOT NULL;", },
  ])
  assert_eq(@moonddl_guard.compare_batches(old, edited).exit_code(), 1)
  inputs.push({ path: "02.sql", sql: "DROP TABLE t;", })
  let current = batch(inputs)
  let delta = @moonddl_guard.compare_batches(old, current)
  assert_eq(delta.exit_code(), 1)
  assert_eq(
    @moonddl_guard.decode_batch_delta(delta.to_json().stringify()).to_json(),
    delta.to_json(),
  )
  assert_eq(@moonddl_guard.compare_batches(current, current).exit_code(), 0)
  let renamed = batch([{ path: "renamed.sql", sql: inputs[0].sql, }])
  assert_true(
    try {
      ignore(@moonddl_guard.compare_batches(old, renamed))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@moonddl_guard.compare_batches(current, old))
      false
    } catch {
      _ => true
    },
  )
  let reordered = batch([inputs[1], inputs[0]])
  assert_true(
    try {
      ignore(@moonddl_guard.compare_batches(current, reordered))
      false
    } catch {
      _ => true
    },
  )
  let broken = batch([{ path: "01.sql", sql: "DO $$ BEGIN NULL; END $$;", }])
  assert_eq(@moonddl_guard.compare_batches(old, broken).exit_code(), 2)
  assert_true(
    try {
      ignore(@moonddl_guard.compare_batches(broken, old))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @moonddl_guard.decode_batch_delta(
          delta
          .to_json()
          .stringify()
          .replace_all(old="\"exit_code\":1", new="\"exit_code\":0"),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "committed file boundary releases tracked locks without inventing inherited settings" {
  let r = batch([
    {
      path: "01.sql",
      sql: "BEGIN; ALTER TABLE t ADD a int; COMMIT; SET lock_timeout='1s';",
    },
    {
      path: "02.sql",
      sql: "UPDATE t SET a=1 WHERE id=1; CREATE INDEX i ON t(id);",
    },
  ])
  assert_true(r.is_complete())
  assert_false(
    r.files()[1].review
    .findings()
    .any(f => {
      f.code == "PG803" || (f.code == "PG305" && f.message.contains("1000ms"))
    }),
  )
  let active = @moonddl_guard.review_isolated_files(
    [{ path: "01.sql", sql: "UPDATE t SET a=1 WHERE id=1", }],
    transaction=@moonddl_guard.Active,
    delivery=@moonddl_guard.SimpleQuery,
  )
  assert_true(
    try {
      ignore(@moonddl_guard.compare_batches(r, active))
      false
    } catch {
      _ => true
    },
  )
}
