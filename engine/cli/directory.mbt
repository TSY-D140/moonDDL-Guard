///|
fn directory_text(path : String) -> String raise {
  let bytes = @fs.read_file_to_bytes(path) catch {
    _ => raise @guard.BatchError::InvalidBatch("Cannot read file: " + path)
  }
  if bytes.length() > 33554432 {
    raise @guard.BatchError::InvalidBatch(
      "Input artifact/file exceeds 32 MiB: " + path,
    )
  }
  @utf8.decode(bytes) catch {
    _ =>
      raise @guard.BatchError::InvalidBatch("File is not valid UTF-8: " + path)
  }
}

///|
// Inventory is exhaustive within a bounded caller-supplied migration directory.
// No default excludes (.git, hidden files, vendor directories) hide SQL inputs.
fn directory_inventory(
  root : String,
  relative : String,
  depth : Int32,
  paths : Array[String],
  budget : Int32,
) -> Int32 raise {
  if depth > 16 {
    raise @guard.BatchError::InvalidBatch(
      "Directory depth exceeds 16; check the migration root and filesystem aliases: " +
      relative,
    )
  }
  let here = if relative == "" { root } else { root + "/" + relative }
  let names = @fs.read_dir(here) catch {
    _ =>
      raise @guard.BatchError::InvalidBatch(
        "Cannot enumerate directory: " + here,
      )
  }
  let mut remaining = budget - names.length()
  if remaining < 0 {
    raise @guard.BatchError::InvalidBatch(
      "Directory inventory exceeds 4096 entries; select a narrower migration directory.",
    )
  }
  for name in names {
    if name == "" ||
      name == "." ||
      name == ".." ||
      name.contains("/") ||
      name.contains("\\") {
      raise @guard.BatchError::InvalidBatch(
        "Unexpected directory entry: " + name,
      )
    }
    let path = if relative == "" { name } else { relative + "/" + name }
    let full = root + "/" + path
    if @fs.is_dir(full) {
      remaining = directory_inventory(root, path, depth + 1, paths, remaining)
    } else if path.to_lower().has_suffix(".sql") {
      if !@fs.is_file(full) {
        raise @guard.BatchError::InvalidBatch(
          "SQL input is not a readable file: " + path,
        )
      }
      paths.push(path)
      if paths.length() > 256 {
        raise @guard.BatchError::InvalidBatch(
          "Directory exceeds 256 SQL files; choose a smaller committed-file review scope.",
        )
      }
    }
  }
  remaining
}

///|
fn directory_main(args : Array[String]) -> Int32 raise {
  if args.length() < 2 {
    raise @guard.BatchError::InvalidBatch(
      "Supply a migration directory or recorded batch artifact.",
    )
  }
  let mut json = false
  let mut replay = false
  let mut order : String? = None
  let mut boundaries = false
  let mut baseline : String? = None
  let mut transaction = @guard.UnknownTransaction
  let mut delivery = @guard.UnknownDelivery
  let mut overrides = false
  for arg in args[2:] {
    match arg {
      "--directory" => ()
      "--json" => json = true
      "--replay" => replay = true
      "--boundaries=per-file" => boundaries = true
      option if option.has_prefix("--order=") =>
        order = Some(option[8:].to_owned())
      option if option.has_prefix("--baseline=") =>
        baseline = Some(option[11:].to_owned())
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
        raise @guard.BatchError::InvalidBatch(
          "Unsupported directory option: " + arg,
        )
    }
  }
  let batch = if replay {
    if overrides || boundaries || order is Some(_) {
      raise @guard.BatchError::InvalidBatch(
        "Batch replay uses recorded order/boundaries/context; omit overrides.",
      )
    }
    @guard.decode_batch(directory_text(args[1]))
  } else {
    guard boundaries && order is Some(order) else {
      raise @guard.BatchError::InvalidBatch(
        "Directory review requires --order=PLAN.json|lexicographic and --boundaries=per-file. Cross-file transactions are unsupported; inherited session settings remain unknown.",
      )
    }
    let inventory : Array[String] = []
    ignore(directory_inventory(args[1], "", 0, inventory, 4096))
    inventory.sort()
    let paths = if order == "lexicographic" {
      @guard.decode_file_order(
        Json({ "format": Json("moonddl.order.v1"), "files": Json(inventory) }).stringify(),
      )
    } else {
      @guard.decode_file_order(directory_text(order))
    }
    if paths.length() != inventory.length() ||
      !paths.all(path => inventory.contains(path)) {
      raise @guard.BatchError::InvalidBatch(
        "Order manifest does not match SQL inventory. Unlisted: " +
        inventory.filter(path => !paths.contains(path)).join(", ") +
        "; missing: " +
        paths.filter(path => !inventory.contains(path)).join(", ") +
        ". Review inventory changes explicitly.",
      )
    }
    let inputs : Array[@guard.MigrationInput] = []
    for path in paths {
      inputs.push({ path, sql: directory_text(args[1] + "/" + path), })
    }
    @guard.review_isolated_files(inputs, transaction~, delivery~)
  }
  if baseline is Some(file) {
    let delta = @guard.compare_batches(
      @guard.decode_batch(directory_text(file)),
      batch,
    )
    println(if json { delta.to_json().stringify() } else { delta.to_text() })
    delta.exit_code()
  } else {
    println(if json { batch.to_json().stringify() } else { batch.to_text() })
    batch.exit_code()
  }
}
