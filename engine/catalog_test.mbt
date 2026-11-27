///|
fn catalog_fixture() -> String {
  (
    #|{"format":"moonddl.catalog.v1","postgres":18,"source":"orders-ci","snapshot_id":"before-001","captured_at":"2026-01-01T00:00:00Z","tables":[{"schema":"public","name":"orders","kind":"ordinary","columns":[{"name":"id","data_type":"integer","not_null":true}],"indexes":[{"name":"idx","unique":true,"valid":true,"ready":true,"live":true,"immediate":true,"btree":true,"partial":false,"expression":false,"default_order":true,"owned":false,"keys":["id"]}]}]}
  )
}

///|
fn catalog_case(
  source : String,
  text : String,
) -> @moonddl_guard.CatalogReview raise {
  @moonddl_guard.review_with_catalog(
    source,
    @moonddl_guard.decode_catalog(text),
    expected_source="orders-ci",
    expected_snapshot="before-001",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
}

///|
fn catalog_status(
  value : @moonddl_guard.CatalogReview,
  expected : String,
) -> Unit raise {
  guard value.to_json() is { "checks": Array(checks), .. } else {
    fail("checks")
  }
  assert_true(
    checks[0] is { "status": String(status), .. } && status == expected,
  )
}

///|
test "catalog records resolved preconditions without lowering static findings" {
  let sql = "ALTER TABLE public.orders ADD CONSTRAINT pk PRIMARY KEY USING INDEX idx;"
  let r = catalog_case(sql, catalog_fixture())
  catalog_status(r, "observed_pass")
  let base = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  guard r.to_json() is { "review": retained, .. } else { fail("base") }
  assert_eq(retained, base.to_json())
  assert_eq(r.exit_code(), base.exit_code())
  assert_eq(
    r.to_json(),
    @moonddl_guard.decode_catalog_review(r.to_json().stringify()).to_json(),
  )
  let nullable = catalog_case(
    sql,
    catalog_fixture().replace_all(
      old="\"not_null\":true",
      new="\"not_null\":false",
    ),
  )
  catalog_status(nullable, "observed_pass")
  assert_true(nullable.to_json().stringify().contains("recorded nullable"))
}

///|
test "each failing attachment precondition is independently observable" {
  let sql = "ALTER TABLE public.orders ADD CONSTRAINT uq UNIQUE USING INDEX idx;"
  for
    (field, old, new) in [
      ("kind", "\"ordinary\"", "\"partitioned\""),
      ("unique", "true", "false"),
      ("valid", "true", "false"),
      ("ready", "true", "false"),
      ("live", "true", "false"),
      ("immediate", "true", "false"),
      ("btree", "true", "false"),
      ("partial", "false", "true"),
      ("expression", "false", "true"),
      ("default_order", "true", "false"),
      ("owned", "false", "true"),
    ] {
    let changed = catalog_fixture().replace_all(
      old="\"" + field + "\":" + old,
      new="\"" + field + "\":" + new,
    )
    let r = catalog_case(sql, changed)
    catalog_status(r, "observed_fail")
    assert_eq(r.exit_code(), 1)
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_catalog_review(r.to_json().stringify()).to_json(),
    )
  }
}

///|
test "partial snapshots and prior mutations never invent current catalog state" {
  for
    sql in [
      "ALTER TABLE orders ADD CONSTRAINT uq UNIQUE USING INDEX idx;", "ALTER TABLE other.orders ADD CONSTRAINT uq UNIQUE USING INDEX idx;",
      "ALTER TABLE public.orders ADD CONSTRAINT uq UNIQUE USING INDEX missing;",
      "ALTER TABLE public.orders ADD a int; ALTER TABLE public.orders ADD CONSTRAINT uq UNIQUE USING INDEX idx;",
      "DO $$ BEGIN NULL; END $$; COMMIT; ALTER TABLE public.orders ADD CONSTRAINT uq UNIQUE USING INDEX idx;",
      "BEGIN; SAVEPOINT s; ALTER TABLE public.orders ADD a int; ROLLBACK TO s; ALTER TABLE public.orders ADD CONSTRAINT uq UNIQUE USING INDEX idx;",
    ] {
    catalog_status(catalog_case(sql, catalog_fixture()), "unknown")
  }
  catalog_status(
    catalog_case(
      "BEGIN; SET LOCAL lock_timeout='1s'; ALTER TABLE public.orders ADD CONSTRAINT uq UNIQUE USING INDEX idx;",
      catalog_fixture(),
    ),
    "observed_pass",
  )
}

///|
test "catalog rejects duplicate unknown missing malformed and inconsistent data" {
  for
    text in [
      "{",
      catalog_fixture() + " trailing",
      catalog_fixture().replace_all(
        old="\"postgres\":18",
        new="\"postgres\":17",
      ),
      catalog_fixture().replace_all(
        old="\"postgres\":18",
        new="\"postgres\":18,\"postgres\":18",
      ),
      catalog_fixture().replace_all(
        old="\"ready\":true",
        new="\"ready\":true,\"r\\u0065ady\":false",
      ),
      catalog_fixture().replace_all(old="\"ready\":true,", new=""),
      catalog_fixture().replace_all(
        old="\"ready\":true",
        new="\"ready\":\"true\"",
      ),
      catalog_fixture().replace_all(
        old="\"keys\":[\"id\"]",
        new="\"keys\":[\"unknown\"]",
      ),
      catalog_fixture().replace_all(
        old="\"keys\":[\"id\"]",
        new="\"keys\":[\"id\",\"id\"]",
      ),
      catalog_fixture().replace_all(old="\"keys\":[\"id\"]", new="\"keys\":[]"),
      catalog_fixture().replace_all(
        old="\"name\":\"idx\"",
        new="\"extra\":1,\"name\":\"idx\"",
      ),
      catalog_fixture().replace_all(
        old="\"source\":\"orders-ci\"",
        new="\"source\":\"\"",
      ),
    ] {
    let rejected = try {
      ignore(@moonddl_guard.decode_catalog(text))
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=text)
  }
  let good = @moonddl_guard.decode_catalog(catalog_fixture())
  assert_eq(
    good.to_json(),
    @moonddl_guard.decode_catalog(good.to_json().stringify()).to_json(),
  )
}

///|
test "catalog provenance mismatch and altered replay fail closed" {
  let c = @moonddl_guard.decode_catalog(catalog_fixture())
  for (origin, id) in [("wrong", "before-001"), ("orders-ci", "stale")] {
    let rejected = try {
      ignore(
        @moonddl_guard.review_with_catalog(
          "",
          c,
          expected_source=origin,
          expected_snapshot=id,
          transaction=@moonddl_guard.Autocommit,
          delivery=@moonddl_guard.PerStatement,
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let r = catalog_case(
    "ALTER TABLE public.orders ADD CONSTRAINT uq UNIQUE USING INDEX idx;",
    catalog_fixture(),
  )
  for
    text in [
      r
      .to_json()
      .stringify()
      .replace_all(old="observed_pass", new="observed_fail"),
      r
      .to_json()
      .stringify()
      .replace_all(old="\"exit_code\":1", new="\"exit_code\":0"),
    ] {
    let rejected = try {
      ignore(@moonddl_guard.decode_catalog_review(text))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "catalog JSON views are defensive and evidence cannot complete unsupported SQL" {
  let c = @moonddl_guard.decode_catalog(catalog_fixture())
  let before = c.to_json()
  guard c.to_json() is { "tables": Array(tables), .. } else { fail("tables") }
  tables.clear()
  assert_eq(before, c.to_json())
  let r = catalog_case(
    "SELECT custom(); ALTER TABLE public.orders ADD CONSTRAINT uq UNIQUE USING INDEX idx;",
    catalog_fixture(),
  )
  assert_eq(r.exit_code(), 2)
  let stable = r.to_json()
  guard r.to_json() is { "checks": Array(checks), .. } else { fail("checks") }
  checks.clear()
  assert_eq(stable, r.to_json())
}

///|
test "catalog size and member limits reject rather than truncate" {
  let too_big = Array::makei(1048577, _ => " ").join("")
  assert_true(
    try {
      ignore(@moonddl_guard.decode_catalog(too_big))
      false
    } catch {
      _ => true
    },
  )
  let name = Array::makei(22, _ => "中").join("")
  let text = catalog_fixture().replace_all(
    old="\"schema\":\"public\"",
    new="\"schema\":\"" + name + "\"",
  )
  assert_true(
    try {
      ignore(@moonddl_guard.decode_catalog(text))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "catalog exact Unicode identities do not infer search path or case folding" {
  let text = catalog_fixture()
    .replace_all(old="public", new="公共")
    .replace_all(old="orders\"", new="订单\"")
    .replace_all(old="\"idx\"", new="\"索引\"")
  catalog_status(
    catalog_case(
      "ALTER TABLE \"公共\".\"订单\" ADD CONSTRAINT uq UNIQUE USING INDEX \"索引\";",
      text,
    ),
    "observed_pass",
  )
  catalog_status(
    catalog_case(
      "ALTER TABLE public.\"Orders\" ADD CONSTRAINT uq UNIQUE USING INDEX idx;",
      catalog_fixture(),
    ),
    "unknown",
  )
  let full = @json.parse(catalog_fixture())
  guard full is { "tables": Array(tables), .. } else { fail("fixture") }
  let table = tables[0].stringify()
  let too_many = catalog_fixture().replace_all(
    old="\"tables\":[" + table + "]",
    new="\"tables\":[" + Array::makei(129, _ => table).join(",") + "]",
  )
  assert_true(
    try {
      ignore(@moonddl_guard.decode_catalog(too_many))
      false
    } catch {
      _ => true
    },
  )
}
