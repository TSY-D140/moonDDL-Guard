///|
fn data_review(sql : String, grouped~ : Bool = false) -> @moonddl_guard.Review {
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
test "data migration reviews bounded expression joins defaults casts and returning" {
  for
    sql in [
      "UPDATE public.orders AS o SET status='done', amount=o.amount+1 WHERE o.id>=1 AND o.id<1000 RETURNING o.id",
      "UPDATE t SET a=DEFAULT,b=COALESCE(a,0),c=CAST(a AS bigint) WHERE id IN (1,2)",
      "UPDATE t SET a=a::numeric(12,2),stamp=now() WHERE a BETWEEN 1 AND 10", "UPDATE website_event w SET hostname=s.hostname FROM session s WHERE s.website_id=w.website_id AND s.session_id=w.session_id",
      "UPDATE t SET a=s.a FROM source s LEFT JOIN other o ON s.id=o.id WHERE t.id=s.id",
      "DELETE FROM orders o USING retired r WHERE o.id=r.id RETURNING o.*", "DELETE FROM t USING a,b WHERE t.id=a.id AND a.id=b.id",
      "DELETE FROM ONLY t WHERE a IS NOT NULL RETURNING id AS removed",
    ] {
    let r = data_review(sql)
    assert_true(r.is_complete(), msg=sql)
    assert_eq(r.exit_code(), 1)
    assert_eq(r.findings().filter(f => f.code == "PG801").length(), 1)
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
}

///|
test "WHERE presence never proves a small or safe data change" {
  for
    sql in [
      "UPDATE t SET a=0", "UPDATE t SET a=0 WHERE TRUE", "DELETE FROM t", "DELETE FROM t WHERE TRUE",
    ] {
    let r = data_review(sql)
    assert_true(r.is_complete())
    assert_eq(r.findings().filter(f => f.code == "PG802").length(), 1)
  }
  for
    sql in [
      "UPDATE t SET a=0 WHERE id>0", "DELETE FROM t WHERE FALSE", "DELETE FROM t WHERE 1=1",
    ] {
    let r = data_review(sql)
    assert_true(r.is_complete())
    assert_eq(r.exit_code(), 1)
    assert_eq(r.findings().filter(f => f.code == "PG801").length(), 1)
  }
}

///|
test "data changes see renamed and joined table locks with savepoint rollback" {
  let r = data_review(
    "SET lock_timeout='100ms'; BEGIN; ALTER TABLE t ADD COLUMN stamp int; ALTER TABLE t RENAME TO fresh; UPDATE fresh SET stamp=1 WHERE id<100; DELETE FROM fresh WHERE id<10; COMMIT;",
  )
  assert_true(r.is_complete())
  assert_eq(r.findings().filter(f => f.code == "PG803").length(), 2)
  assert_eq(r.findings().filter(f => f.code == "PG804").length(), 2)
  assert_eq(r.findings().filter(f => f.code == "PG305").length(), 4)
  let rollback = data_review(
    "BEGIN; SAVEPOINT p; ALTER TABLE t ADD COLUMN a int; ROLLBACK TO p; UPDATE t SET a=1 WHERE id<10; COMMIT;",
  )
  assert_eq(rollback.findings().filter(f => f.code == "PG803").length(), 0)
  let joined = data_review(
    "BEGIN; ALTER TABLE source ADD COLUMN a int; UPDATE t SET a=s.a FROM source s WHERE t.id=s.id; COMMIT;",
  )
  assert_eq(joined.findings().filter(f => f.code == "PG803").length(), 1)
  let separate = data_review(
    "ALTER TABLE t ADD COLUMN a int; UPDATE t SET a=1 WHERE id<10;",
  )
  assert_eq(separate.findings().filter(f => f.code == "PG803").length(), 0)
  assert_eq(
    data_review(
      "UPDATE t SET a=1 WHERE id<10; DELETE FROM t WHERE id<10;",
      grouped=true,
    )
    .findings()
    .filter(f => f.code == "PG804")
    .length(),
    2,
  )
}

///|
test "duplicate assignments reject aliases folded names but preserve quoted case" {
  let duplicate = data_review("UPDATE t SET a=1,A=2 WHERE id=1")
  assert_false(duplicate.is_complete())
  assert_eq(duplicate.exit_code(), 2)
  assert_eq(duplicate.findings().filter(f => f.code == "PG810").length(), 1)
  assert_true(data_review("UPDATE t SET a=1,\"A\"=2 WHERE id=1").is_complete())
  assert_false(data_review("UPDATE t SET t.a=1 WHERE id=1").is_complete())
}

///|
test "data grammar rejects unassessed clauses expressions and malformed SQL losslessly" {
  for
    sql in [
      "UPDATE t SET", "UPDATE t SET a=", "DELETE FROM", "UPDATE t SET a=custom(a) WHERE id=1",
      "UPDATE t SET a=(SELECT 1)", "UPDATE t SET (a,b)=(1,2)", "DELETE FROM t WHERE id IN (SELECT id FROM s)",
      "UPDATE t SET a=1 LIMIT 1", "DELETE FROM t LIMIT 1", "DELETE FROM t WHERE CURRENT OF c",
      "WITH x AS (DELETE FROM s RETURNING *) DELETE FROM t USING x WHERE t.id=x.id",
      "UPDATE t SET a=1 WHERE DEFAULT", "UPDATE t SET a=COALESCE(DEFAULT,1)",
    ] {
    let r = data_review(sql)
    assert_false(r.is_complete(), msg=sql)
    assert_eq(r.exit_code(), 2)
    assert_eq(r.statements()[0].sql, sql)
  }
}

///|
test "data migration report delta SARIF source positions and malformed prefixes are deterministic" {
  let sql = "-- 😀\r\nUPDATE t SET a=1 WHERE id<10 RETURNING id; DELETE FROM t WHERE id<2;"
  let r = data_review(sql)
  assert_eq(r.findings()[0].location.line, 2)
  let delta = @moonddl_guard.compare_reviews(data_review(""), r)
  assert_eq(delta.exit_code(), 1)
  assert_eq(
    delta.to_json(),
    @moonddl_guard.decode_delta(delta.to_json().stringify()).to_json(),
  )
  assert_eq(
    r.to_sarif("migrations/data.sql"),
    r.to_sarif("migrations/data.sql"),
  )
  for
    prefix_sql in [
      "UPDATE t SET a=s.a FROM s WHERE t.id=s.id", "DELETE FROM t WHERE id<2 RETURNING id",
    ] {
    for i in 0..<=prefix_sql.length() {
      let review = data_review(prefix_sql[:i].to_owned())
      assert_eq(
        review.to_json(),
        @moonddl_guard.decode_report(review.to_json().stringify()).to_json(),
      )
    }
  }
}
