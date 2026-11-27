///|
priv struct CatalogColumn {
  name : String
  data_type : String
  not_null : Bool
} derive(ToJson, @json.FromJson)

///|
priv struct CatalogIndex {
  name : String
  unique : Bool
  valid : Bool
  ready : Bool
  live : Bool
  immediate : Bool
  btree : Bool
  partial : Bool
  expression : Bool
  default_order : Bool
  owned : Bool
  keys : Array[String]
} derive(ToJson, @json.FromJson)

///|
priv struct CatalogTable {
  schema : String
  name : String
  kind : String
  columns : Array[CatalogColumn]
  indexes : Array[CatalogIndex]
} derive(ToJson, @json.FromJson)

///|
priv struct CatalogData {
  format : String
  postgres : Int32
  source : String
  snapshot_id : String
  captured_at : String
  tables : Array[CatalogTable]
} derive(ToJson, @json.FromJson)

///|
/// Caller-provided, partial PostgreSQL 18 evidence. No live connection or freshness proof.
pub struct CatalogSnapshot {
  priv data : CatalogData
}

///|
pub fn CatalogSnapshot::to_json(self : CatalogSnapshot) -> Json {
  ToJson::to_json(self.data)
}

///|
fn catalog_text(value : String, limit : Int32) -> Bool {
  !value.is_empty() &&
  value.length() <= limit &&
  value.iter().all(c => c.to_int() >= 32 && c.to_int() != 127)
}

///|
fn catalog_name(value : String) -> Bool {
  catalog_text(value, 63) && @utf8.encode(value).length() <= 63
}

///|
/// Decode a strict, bounded partial snapshot. Missing objects never prove absence.
///
/// ```mbt check
/// test {
///   let text = "{\"format\":\"moonddl.catalog.v1\",\"postgres\":18,\"source\":\"dev\",\"snapshot_id\":\"before-001\",\"captured_at\":\"caller record\",\"tables\":[]}"
///   let snapshot = @moonddl_guard.decode_catalog(text)
///   assert_eq(
///     snapshot.to_json(),
///     @moonddl_guard.decode_catalog(snapshot.to_json().stringify()).to_json(),
///   )
/// }
/// ```
pub fn decode_catalog(text : String) -> CatalogSnapshot raise ReportError {
  if text.length() > 1048576 {
    raise InvalidReport("Catalog exceeds 1 Mi UTF-16 units.")
  }
  let value = batch_json(text)
  let data : CatalogData = @json.from_json(value) catch {
    _ => raise InvalidReport("Invalid catalog shape or field types.")
  }
  if data.format != "moonddl.catalog.v1" ||
    data.postgres != 18 ||
    !catalog_text(data.source, 256) ||
    !catalog_text(data.snapshot_id, 256) ||
    !catalog_text(data.captured_at, 128) ||
    data.tables.length() > 128 ||
    ToJson::to_json(data) != value {
    raise InvalidReport(
      "Unsupported catalog version, provenance, table bound or unknown/missing fields.",
    )
  }
  let tables : Map[String, Bool] = Map([])
  let indexes : Map[String, Bool] = Map([])
  for table in data.tables {
    let key = Json([table.schema, table.name]).stringify()
    if !catalog_name(table.schema) ||
      !catalog_name(table.name) ||
      !["ordinary", "partitioned"].contains(table.kind) ||
      tables.contains(key) ||
      table.columns.is_empty() ||
      table.columns.length() > 256 ||
      table.indexes.length() > 256 {
      raise InvalidReport(
        "Invalid/duplicate table or catalog member bound: " + key,
      )
    }
    tables[key] = true
    let columns : Map[String, Bool] = Map([])
    for column in table.columns {
      if !catalog_name(column.name) ||
        !catalog_text(column.data_type, 1024) ||
        columns.contains(column.name) {
        raise InvalidReport("Invalid/duplicate column on " + key)
      }
      columns[column.name] = true
    }
    for index in table.indexes {
      let index_key = Json([table.schema, index.name]).stringify()
      if !catalog_name(index.name) ||
        indexes.contains(index_key) ||
        index.keys.length() > 32 ||
        (index.keys.is_empty() && !index.expression) {
        raise InvalidReport(
          "Invalid/duplicate index or key bound: " + index_key,
        )
      }
      indexes[index_key] = true
      let keys : Map[String, Bool] = Map([])
      for name in index.keys {
        if !columns.contains(name) || keys.contains(name) {
          raise InvalidReport("Missing/duplicate index key: " + index_key)
        }
        keys[name] = true
      }
    }
  }
  { data, }
}

///|
pub struct CatalogReview {
  priv review : Review
  priv catalog : CatalogSnapshot
  priv checks : Array[CatalogCheck]
}

///|
priv struct CatalogCheck {
  statement : Int32
  status : String
  details : Array[String]
} derive(ToJson)

///|
pub fn CatalogReview::to_json(self : CatalogReview) -> Json {
  {
    "format": "moonddl.catalog-review.v1",
    "review": self.review.to_json(),
    "catalog": self.catalog.to_json(),
    "checks": Json(self.checks),
    "exit_code": self.exit_code(),
  }
}

///|
/// Evidence never lowers the static gate; a failed observed precondition raises risk.
pub fn CatalogReview::exit_code(self : CatalogReview) -> Int32 {
  let base = self.review.exit_code()
  if base == 2 {
    2
  } else if self.checks.any(c => c.status == "observed_fail") {
    1
  } else {
    base
  }
}

///|
fn attachment_evidence(
  part : Segment,
  snapshot : CatalogSnapshot,
  number : Int32,
) -> CatalogCheck {
  let unknown = fn(message) {
    CatalogCheck::{ statement: number, status: "unknown", details: [message], }
  }
  let spec = match constraint_spec(part) {
    Some(s) => s
    None => return unknown("Outside index-attachment evidence profile.")
  }
  guard spec.action is AttachIndex(primary) else {
    return unknown("Outside index-attachment evidence profile.")
  }
  let names = @json.parse(spec.table_key) catch {
    _ => return unknown("Unresolved table identity.")
  }
  guard names is Array(parts) && parts.length() == 2 else {
    return unknown(
      "Schema qualification required; search_path is not inferred.",
    )
  }
  guard parts[0] is String(schema) && parts[1] is String(name) else {
    return unknown("Unresolved table identity.")
  }
  let token = part.tokens[part.tokens.length() - 1]
  let index_name = if token.token_type == @syntax.IDENTIFIER {
    token.text
  } else {
    token.text.to_lower()
  }
  let table = match
    snapshot.data.tables
    .iter()
    .find_first(t => t.schema == schema && t.name == name) {
    Some(t) => t
    None =>
      return unknown(
        "Table not in this partial snapshot; absence is not established.",
      )
  }
  let index = match table.indexes.iter().find_first(i => i.name == index_name) {
    Some(i) => i
    None =>
      return unknown(
        "Index not in this partial snapshot; absence is not established.",
      )
  }
  let details : Array[String] = []
  for
    (ok, reason) in [
      (table.kind == "ordinary", "Table is partitioned."),
      (index.unique, "Index is not unique."),
      (index.valid, "Index is invalid."),
      (index.ready, "Index is not ready."),
      (index.live, "Index is not live."),
      (index.immediate, "Index is not immediate."),
      (index.btree, "Index is not B-tree."),
      (!index.partial, "Index has a predicate."),
      (!index.expression, "Index has expression keys."),
      (
        index.default_order,
        "Index uses nondefault ordering/operator/collation settings.",
      ),
      (!index.owned, "Index already backs a constraint."),
    ] {
    if !ok {
      details.push(reason)
    }
  }
  let nullable = table.columns.filter(c => {
    index.keys.contains(c.name) && !c.not_null
  })
  if details.is_empty() {
    details.push(
      "Recorded attachment preconditions match at the declared snapshot; this is not live eligibility or safety certification.",
    )
    if primary && !nullable.is_empty() {
      details.push(
        "Primary-key key columns include recorded nullable columns; NOT NULL validation may still be needed.",
      )
    } else if primary {
      details.push(
        "All recorded primary-key columns are NOT NULL at the snapshot; current data/catalog and lock acquisition remain unverified.",
      )
    }
    { statement: number, status: "observed_pass", details, }
  } else {
    { statement: number, status: "observed_fail", details, }
  }
}

///|
/// Apply opt-in snapshot evidence without replacing static findings or execution context.
/// The caller must confirm both provenance labels; neither label proves freshness.
pub fn review_with_catalog(
  source : String,
  catalog : CatalogSnapshot,
  expected_source~ : String,
  expected_snapshot~ : String,
  transaction~ : Transaction,
  delivery~ : Delivery,
) -> CatalogReview raise ReportError {
  if expected_source != catalog.data.source ||
    expected_snapshot != catalog.data.snapshot_id {
    raise InvalidReport(
      "Catalog source/snapshot mismatch; select evidence for the intended database and migration point.",
    )
  }
  let review = review_sql(source, transaction~, delivery~)
  let checks : Array[CatalogCheck] = []
  let parts = if source.length() > 262144 {
    []
  } else {
    segments(source) catch {
      _ => []
    }
  }
  let mut prior_change = false
  for i, part in parts {
    if i >= review.statements.length() {
      break
    }
    let statement = review.statements[i]
    if statement.operation == "attach_primary_key" ||
      statement.operation == "attach_unique_constraint" {
      checks.push(
        if prior_change {
          {
            statement: i + 1,
            status: "unknown",
            details: [
              "Earlier SQL may have changed catalog/data; a pre-file snapshot is not replayed as live state.",
            ],
          }
        } else {
          attachment_evidence(part, catalog, i + 1)
        },
      )
    }
    // Only known transaction/timeout controls preserve the pre-file snapshot.
    if transaction_step(part.tokens) is None &&
      savepoint_step(part.tokens) is None &&
      timeout_setting(part.tokens) is None {
      prior_change = true
    }
    if statement.coverage != Analyzed {
      prior_change = true
    }
  }
  let result = CatalogReview::{ review, catalog, checks, }
  if result.to_json().stringify().length() > 8388608 {
    raise InvalidReport("Catalog review exceeds the 8 Mi replay bound.")
  }
  result
}

///|
pub fn decode_catalog_review(text : String) -> CatalogReview raise ReportError {
  let value = batch_json(text)
  guard value
    is {
      "format": String("moonddl.catalog-review.v1"),
      "review": base,
      "catalog": evidence,
      ..
    } else {
    raise InvalidReport("Expected moonddl.catalog-review.v1.")
  }
  let review = decode_report(base.stringify())
  let catalog = decode_catalog(evidence.stringify())
  let result = review_with_catalog(
    review.source,
    catalog,
    expected_source=catalog.data.source,
    expected_snapshot=catalog.data.snapshot_id,
    transaction=review.transaction,
    delivery=review.delivery,
  )
  if result.to_json() != value {
    raise InvalidReport("Unknown/missing fields or altered evidence verdict.")
  }
  result
}
