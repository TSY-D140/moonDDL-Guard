///|
fn fk_review(sql : String, grouped~ : Bool = false) -> @moonddl_guard.Review {
  @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=if grouped {
      @moonddl_guard.SimpleQuery
    } else {
      @moonddl_guard.PerStatement
    },
  )
}

///|
test "foreign keys distinguish immediate and staged validation with both table locks" {
  let add = "ALTER TABLE orders ADD CONSTRAINT customer_fk FOREIGN KEY (customer_id) REFERENCES customers(id)"
  let immediate = fk_review(add)
  assert_true(immediate.is_complete())
  assert_eq(immediate.findings().map(f => f.code), ["PG415", "PG416", "PG418"])
  let phases = add +
    " NOT VALID; ALTER TABLE orders VALIDATE CONSTRAINT customer_fk;"
  let separate = fk_review(phases)
  assert_true(separate.is_complete())
  assert_eq(separate.findings().filter(f => f.code == "PG421").length(), 0)
  assert_eq(separate.findings().filter(f => f.code == "PG417").length(), 1)
  let together = fk_review(phases, grouped=true)
  assert_eq(together.findings().filter(f => f.code == "PG421").length(), 1)
  assert_eq(together.findings().filter(f => f.code == "PG405").length(), 0)
  assert_eq(
    together.to_json(),
    @moonddl_guard.decode_report(together.to_json().stringify()).to_json(),
  )
}

///|
test "foreign grammar covers composite keys omitted referenced keys and actions" {
  for
    tail in [
      "FOREIGN KEY (tenant_id, customer_id) REFERENCES public.customers(tenant_id, id) MATCH FULL ON DELETE CASCADE ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED NOT VALID",
      "FOREIGN KEY (customer_id) REFERENCES customers ON UPDATE SET DEFAULT ON DELETE SET NULL NOT DEFERRABLE INITIALLY IMMEDIATE",
      "FOREIGN KEY (\"客户\") REFERENCES \"客户表\" (\"编号\") MATCH SIMPLE ON DELETE NO ACTION",
    ] {
    let r = fk_review("ALTER TABLE ONLY orders ADD " + tail)
    assert_true(r.is_complete(), msg=tail)
    assert_eq(r.findings().filter(f => f.code == "PG418").length(), 1)
  }
  let cascade = fk_review(
    "ALTER TABLE t ADD FOREIGN KEY (a) REFERENCES p(id) ON DELETE CASCADE",
  )
  assert_eq(cascade.findings().filter(f => f.code == "PG419").length(), 1)
}

///|
test "foreign retained locks compose with savepoints strong locks and both identities" {
  let add = "ALTER TABLE child ADD FOREIGN KEY (a) REFERENCES parent(id) NOT VALID;"
  for table in ["child", "parent"] {
    let r = fk_review(
      "BEGIN; " +
      add +
      " ALTER TABLE " +
      table +
      " VALIDATE CONSTRAINT c; COMMIT;",
    )
    assert_eq(r.findings().filter(f => f.code == "PG421").length(), 1)
    let reverted = fk_review(
      "BEGIN; SAVEPOINT p; " +
      add +
      " ROLLBACK TO p; ALTER TABLE " +
      table +
      " VALIDATE CONSTRAINT c; COMMIT;",
    )
    assert_eq(reverted.findings().filter(f => f.code == "PG421").length(), 0)
  }
  let strong = fk_review(
    "BEGIN; ALTER TABLE child ALTER COLUMN a SET NOT NULL; " +
    add +
    " ALTER TABLE child VALIDATE CONSTRAINT c; COMMIT;",
  )
  assert_eq(strong.findings().filter(f => f.code == "PG405").length(), 1)
  assert_eq(strong.findings().filter(f => f.code == "PG421").length(), 0)
}

///|
test "foreign unsupported malformed duplicated and oversized clauses never disappear" {
  for
    tail in [
      "FOREIGN KEY () REFERENCES p(id)", "FOREIGN KEY (a,a) REFERENCES p(id,id)",
      "FOREIGN KEY (a,b) REFERENCES p(id)", "FOREIGN KEY (a,) REFERENCES p(id)",
      "FOREIGN KEY (a) REFERENCES p(id) MATCH PARTIAL", "FOREIGN KEY (a) REFERENCES p(id) ON DELETE SET NULL (a)",
      "FOREIGN KEY (a) REFERENCES p(id) ON DELETE CASCADE ON DELETE RESTRICT", "FOREIGN KEY (a) REFERENCES p(id) NOT DEFERRABLE INITIALLY DEFERRED",
      "FOREIGN KEY (a) REFERENCES p(id) NOT ENFORCED", "FOREIGN KEY (a) REFERENCES p(id), DROP COLUMN b",
    ] {
    let sql = "ALTER TABLE t ADD CONSTRAINT fk " + tail + ";"
    let r = fk_review(sql)
    assert_false(r.is_complete(), msg=tail)
    assert_eq(r.statements()[0].sql, sql)
    assert_eq(r.exit_code(), 2)
  }
  let names = StringBuilder()
  for i in 0..<33 {
    if i > 0 {
      names.write_string(",")
    }
    names.write_string("c\{i}")
  }
  assert_false(
    fk_review(
      "ALTER TABLE t ADD FOREIGN KEY (" + names.to_string() + ") REFERENCES p",
    ).is_complete(),
  )
}

///|
test "foreign key report baseline delta and SARIF preserve registered diagnostics" {
  let r = fk_review(
    "-- 😀\r\nALTER TABLE child ADD FOREIGN KEY (a) REFERENCES parent(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED NOT VALID;",
  )
  let delta = @moonddl_guard.compare_reviews(fk_review(""), r)
  assert_eq(delta.exit_code(), 1)
  assert_eq(
    delta.to_json(),
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
  )
  guard r.to_sarif("migrations/fk.sql") is { "runs": Array(runs), .. } else {
    fail("Missing runs")
  }
  guard runs[0]
    is { "tool": { "driver": { "rules": Array(rules), .. }, .. }, .. } else {
    fail("Missing rules")
  }
  for f in r.findings() {
    assert_true(
      rules.any(rule => rule is { "id": String(code), .. } && code == f.code),
    )
    assert_eq(f.location.line, 2)
    assert_eq(f.location.column, 1)
  }
}
