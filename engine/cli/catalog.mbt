///|
fn catalog_main(args : Array[String]) -> Int32 raise {
  let mut snapshot_path : String? = None
  let mut expected_source : String? = None
  let mut expected_snapshot : String? = None
  let mut replay = false
  let mut transaction = @guard.UnknownTransaction
  let mut delivery = @guard.UnknownDelivery
  let mut overrides = false
  if args.length() < 2 {
    raise @guard.ReportError::InvalidReport(
      "Supply SQL or catalog-review file.",
    )
  }
  for option in args[2:] {
    match option {
      "--json" => ()
      "--catalog-replay" => replay = true
      value if value.has_prefix("--catalog=") =>
        snapshot_path = Some(value[10:].to_owned())
      value if value.has_prefix("--catalog-source=") =>
        expected_source = Some(value[17:].to_owned())
      value if value.has_prefix("--catalog-snapshot=") =>
        expected_snapshot = Some(value[19:].to_owned())
      "--transaction=autocommit" => {
        transaction = @guard.Autocommit
        overrides = true
      }
      "--transaction=active" => {
        transaction = @guard.Active
        overrides = true
      }
      "--transaction=unknown" => {
        transaction = @guard.UnknownTransaction
        overrides = true
      }
      "--delivery=statements" => {
        delivery = @guard.PerStatement
        overrides = true
      }
      "--delivery=simple-query" => {
        delivery = @guard.SimpleQuery
        overrides = true
      }
      "--delivery=unknown" => {
        delivery = @guard.UnknownDelivery
        overrides = true
      }
      _ =>
        raise @guard.ReportError::InvalidReport(
          "Unknown/conflicting catalog option: " + option,
        )
    }
  }
  if !args.contains("--json") {
    raise @guard.ReportError::InvalidReport(
      "Catalog evidence mode requires --json; SARIF, directory and baseline combinations are unsupported.",
    )
  }
  let result = if replay {
    if overrides ||
      snapshot_path is Some(_) ||
      expected_source is Some(_) ||
      expected_snapshot is Some(_) {
      raise @guard.ReportError::InvalidReport(
        "Replay uses recorded evidence/context; omit overrides.",
      )
    }
    @guard.decode_catalog_review(directory_text(args[1]))
  } else {
    guard snapshot_path is Some(path) &&
      expected_source is Some(origin) &&
      expected_snapshot is Some(id) else {
      raise @guard.ReportError::InvalidReport(
        "Supply --catalog=FILE, --catalog-source=LABEL and --catalog-snapshot=ID explicitly.",
      )
    }
    @guard.review_with_catalog(
      directory_text(args[1]),
      @guard.decode_catalog(directory_text(path)),
      expected_source=origin,
      expected_snapshot=id,
      transaction~,
      delivery~,
    )
  }
  println(result.to_json().stringify())
  result.exit_code()
}
