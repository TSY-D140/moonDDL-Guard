///|
test "bootstrap definitions preserve ordinary generation and inline constraints" {
  for
    body in [
      "", "id bigint PRIMARY KEY, status text NOT NULL DEFAULT 'pending'", "id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, amount int, total int GENERATED ALWAYS AS (amount*2) STORED",
      "id serial PRIMARY KEY, value text CONSTRAINT uk UNIQUE NULLS NOT DISTINCT",
      "parent_id int REFERENCES parent(id) ON DELETE CASCADE, amount int CHECK (amount >= 0)",
      "id int, CONSTRAINT pk PRIMARY KEY(id), CHECK(id > 0)", "a numeric(12,2) DEFAULT 0 NOT NULL, b timestamptz DEFAULT now()",
    ] {
    let sql = "CREATE TABLE public.orders (" + body + ")"
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].operation, "create_table")
    assert_eq(
      r
      .findings()
      .filter(f => ["PG502", "PG503", "PG514", "PG425"].contains(f.code))
      .length(),
      0,
    )
    assert_eq(
      r.to_json(),
      @moonddl_guard.decode_report(r.to_json().stringify()).to_json(),
    )
  }
}

///|
test "new child creation retains referenced locks with savepoint recovery" {
  let sql = "BEGIN; SAVEPOINT p; CREATE TABLE IF NOT EXISTS child (id int REFERENCES parent(id)); UPDATE parent SET id=2 WHERE id=1; ROLLBACK TO p; UPDATE parent SET id=2 WHERE id=1; COMMIT;"
  let r = @moonddl_guard.review_sql(
    sql,
    transaction=@moonddl_guard.Autocommit,
    delivery=@moonddl_guard.PerStatement,
  )
  assert_true(r.is_complete())
  for (code, count) in [("PG914", 1), ("PG912", 1), ("PG803", 1)] {
    assert_eq(r.findings().filter(f => f.code == code).length(), count)
  }
  for kind in ["TEMP", "TEMPORARY", "UNLOGGED"] {
    let r = @moonddl_guard.review_sql(
      "CREATE " + kind + " TABLE t (id int)",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_true(r.is_complete())
    assert_eq(r.findings().filter(f => f.code == "PG913").length(), 1)
  }
}

///|
test "create table profile rejects unexamined clauses and retains complete input" {
  for
    sql in [
      "CREATE TABLE t AS SELECT 1", "CREATE TABLE t (LIKE parent INCLUDING ALL)",
      "CREATE TABLE t (id int) PARTITION BY HASH(id)", "CREATE TABLE t (id int) INHERITS(parent)",
      "CREATE TABLE t (id int,)", "CREATE TABLE t (,id int)", "CREATE TABLE t (id int, ID text)",
      "CREATE TABLE t (id int DEFAULT custom())", "CREATE TABLE t (id int COLLATE custom)",
      "CREATE TABLE t (id int REFERENCES parent(id) NOT VALID)", "CREATE TABLE t (id int UNIQUE NOT VALID)",
      "CREATE TABLE t (id int NOT NULL DEFAULT 1 NOT NULL)", "CREATE TABLE t (id int PRIMARY KEY NOT NULL)",
      "CREATE TABLE t (id int) TABLESPACE fast", "CREATE TABLE t (id int) ON COMMIT DROP",
    ] {
    let r = @moonddl_guard.review_sql(
      sql,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    )
    assert_false(r.is_complete(), msg=sql)
    assert_eq(r.statements()[0].sql, sql)
  }
  let columns = Array::makei(128, i => "c" + i.to_string() + " int")
  let good = "CREATE TABLE t (" + columns.join(",") + ")"
  assert_true(
    @moonddl_guard.review_sql(
      good,
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
  assert_false(
    @moonddl_guard.review_sql(
      "CREATE TABLE t (" + columns.join(",") + ",overflow int)",
      transaction=@moonddl_guard.Autocommit,
      delivery=@moonddl_guard.PerStatement,
    ).is_complete(),
  )
}
