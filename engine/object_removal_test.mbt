///|
test "object retirement grammar covers named objects and exact routine signatures" {
  for
    (sql, operation) in [
      (
        "DROP VIEW IF EXISTS public.old_view, public.other RESTRICT", "drop_view",
      ),
      ("DROP MATERIALIZED VIEW old_report CASCADE", "drop_materialized_view"),
      ("DROP SEQUENCE IF EXISTS public.counter CASCADE", "drop_sequence"),
      ("DROP TYPE public.state CASCADE", "drop_type"),
      ("DROP DOMAIN positive_amount RESTRICT", "drop_domain"),
      ("DROP SCHEMA archive CASCADE", "drop_schema"),
      ("DROP EXTENSION IF EXISTS hstore CASCADE", "drop_extension"),
      (
        "DROP FUNCTION public.f(integer,text), public.g() RESTRICT", "drop_function",
      ),
      ("DROP PROCEDURE public.p(public.custom_type) CASCADE", "drop_procedure"),
      ("DROP TRIGGER IF EXISTS audit ON public.orders CASCADE", "drop_trigger"),
      ("DROP POLICY IF EXISTS visible ON public.orders CASCADE", "drop_policy"),
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].operation, operation)
    assert_eq(r.findings().filter(f => f.code == "PG631").length(), 1)
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
}

///|
test "policy drop does not invent cascade effects or RLS disabling" {
  let r = @moonddl_guard.review_sql(
    "BEGIN; SAVEPOINT p; DROP POLICY visible ON public.orders CASCADE; UPDATE public.orders SET amount=1 WHERE id=1; ROLLBACK TO p; UPDATE public.orders SET amount=1 WHERE id=2; COMMIT;",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  for (code, count) in [("PG632", 0), ("PG635", 1), ("PG634", 1), ("PG803", 1)] {
    assert_eq(r.findings().filter(f => f.code == code).length(), count)
  }
  let trigger = @moonddl_guard.review_sql(
    "DROP TRIGGER audit ON orders; DROP SEQUENCE counter CASCADE; DROP TYPE status CASCADE;",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(trigger.is_complete())
  for code in ["PG632", "PG636", "PG637"] {
    assert_true(trigger.findings().any(f => f.code == code))
  }
}

///|
test "retirement profile rejects unsupported targets signatures and trailing clauses" {
  let names = Array::makei(32, i => "v" + i.to_string())
  assert_true(
    @moonddl_guard.review_sql(
      "DROP VIEW " + names.join(","),
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
  for
    sql in [
      "DROP VIEW " + names.join(",") + ",overflow",
      "DROP DATABASE app",
      "DROP ROLE app",
      "DROP VIEW v CONCURRENTLY",
      "DROP MATERIALIZED VIEW v WITH DATA",
      "DROP SCHEMA public.archive",
      "DROP EXTENSION public.hstore",
      "DROP TRIGGER public.audit ON orders",
      "DROP POLICY p,q ON orders",
      "DROP FUNCTION f",
      "DROP FUNCTION f(IN id int)",
      "DROP FUNCTION f(int[])",
      "DROP FUNCTION f(int DEFAULT 1)",
      "DROP PROCEDURE p(OUT int)",
      "DROP TYPE t CASCADE RESTRICT",
      "DROP DOMAIN d,",
      "DROP SEQUENCE",
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].sql, sql)
  }
}

///|
test "retirement truncated input recovers deterministically without discarding source" {
  let source = "DROP FUNCTION public.retired(integer,text) CASCADE; DROP TRIGGER audit ON public.orders;"
  for end in 0..<=source.length() {
    let r = @moonddl_guard.review_sql(
      source[0:end].to_owned(),
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
  let r = @moonddl_guard.review_sql(
    "DROP DATABASE app; ROLLBACK; DROP VIEW old;",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_false(r.is_complete())
  assert_eq(r.statements()[2].operation, "drop_view")
  assert_eq(
    r.to_sarif("migrations/retire.sql"),
    r.to_sarif("migrations/retire.sql"),
  )
  let complete = @moonddl_guard.review_sql(
    "DROP VIEW old",
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  let delta = @moonddl_guard.compare_reviews(complete, complete)
  assert_eq(
    delta.to_json(),
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
  )
}
