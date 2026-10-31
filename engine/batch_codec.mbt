///|
fn batch_json(text : String) -> Json raise ReportError {
  if text.length() > 8388608 {
    raise InvalidReport("Batch artifact exceeds the 8 Mi UTF-16 replay limit.")
  }
  let value = @json.parse(text) catch {
    _ => raise InvalidReport("Malformed batch JSON.")
  }
  reject_duplicate_keys(text)
  value
}

///|
/// Decode an exact ordered file plan. Inventory matching belongs to the reader.
pub fn decode_file_order(text : String) -> Array[String] raise ReportError {
  let value = batch_json(text)
  guard value
    is { "format": String("moonddl.order.v1"), "files": Array(entries), .. } else {
    raise InvalidReport(
      "Expected moonddl.order.v1 with an ordered files array.",
    )
  }
  let paths : Array[String] = []
  for entry in entries {
    guard entry is String(path) else {
      raise InvalidReport("Order entries must be relative SQL paths.")
    }
    paths.push(path)
  }
  validate_file_paths(paths) catch {
    error => raise InvalidReport("\{Repr(error)}")
  }
  if value != Json({ "format": Json("moonddl.order.v1"), "files": Json(paths) }) {
    raise InvalidReport("Unknown fields in file order.")
  }
  paths
}

///|
/// Strict replay validates every retained report and recomputes the aggregate.
pub fn decode_batch(text : String) -> BatchReview raise ReportError {
  let value = batch_json(text)
  guard value
    is {
      "format": String("moonddl.batch.v1"),
      "boundaries": String("per-file-commit"),
      "transaction": transaction,
      "delivery": delivery,
      "files": Array(files),
      ..
    } else {
    raise InvalidReport("Expected a per-file-commit moonddl.batch.v1 report.")
  }
  let tx : Transaction = match transaction {
    String("Autocommit") => Autocommit
    String("Active") => Active
    String("UnknownTransaction") => UnknownTransaction
    _ => raise InvalidReport("Unknown batch transaction context.")
  }
  let mode : Delivery = match delivery {
    String("PerStatement") => PerStatement
    String("SimpleQuery") => SimpleQuery
    String("UnknownDelivery") => UnknownDelivery
    _ => raise InvalidReport("Unknown batch delivery context.")
  }
  let inputs : Array[MigrationInput] = []
  for file in files {
    guard file is { "path": String(path), "review": retained, .. } else {
      raise InvalidReport("Missing file path/report.")
    }
    let review = decode_report(retained.stringify())
    inputs.push({ path, sql: review.source, })
  }
  let result = review_isolated_files(inputs, transaction=tx, delivery=mode) catch {
    error => raise InvalidReport("\{Repr(error)}")
  }
  if result.to_json() != value {
    raise InvalidReport(
      "Unknown/missing fields, mixed contexts or inconsistent batch results.",
    )
  }
  result
}

///|
pub fn decode_batch_delta(text : String) -> BatchDelta raise ReportError {
  let value = batch_json(text)
  guard value
    is {
      "format": String("moonddl.batch-delta.v1"),
      "baseline": baseline,
      "current": current,
      ..
    } else {
    raise InvalidReport("Expected moonddl.batch-delta.v1.")
  }
  let result = compare_batches(
    decode_batch(baseline.stringify()),
    decode_batch(current.stringify()),
  ) catch {
    error => raise InvalidReport("\{Repr(error)}")
  }
  if result.to_json() != value {
    raise InvalidReport(
      "Unknown/missing fields or inconsistent batch comparison.",
    )
  }
  result
}
