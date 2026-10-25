///|
// Exact token grammar; no catalog assumptions about the names being removed.
priv struct DropIndexSpec {
  concurrent : Bool
  cascade : Bool
  count : Int32
}

///|
fn qualified_name_end(tokens : Array[@syntax.Token], start : Int32) -> Int32? {
  if start >= tokens.length() ||
    !is_identifier(tokens[start]) ||
    tokens[start].text.is_empty() {
    return None
  }
  let mut i = start + 1
  if i < tokens.length() && tokens[i].token_type == @syntax.DOT {
    i += 1
    if i >= tokens.length() ||
      !is_identifier(tokens[i]) ||
      tokens[i].text.is_empty() {
      return None
    }
    i += 1
  }
  Some(i)
}

///|
fn drop_index_spec(tokens : Array[@syntax.Token]) -> DropIndexSpec? {
  if tokens.length() > 256 ||
    !word(tokens, 0, "DROP") ||
    !word(tokens, 1, "INDEX") {
    return None
  }
  let concurrent = word(tokens, 2, "CONCURRENTLY")
  let mut i = if concurrent { 3 } else { 2 }
  if word(tokens, i, "IF") {
    if !word(tokens, i + 1, "EXISTS") {
      return None
    }
    i += 2
  }
  let mut count = 0
  for ;; {
    i = match qualified_name_end(tokens, i) {
      Some(end) => end
      None => return None
    }
    count += 1
    if count > 32 {
      return None
    }
    if i < tokens.length() && tokens[i].token_type == @syntax.COMMA {
      i += 1
      continue
    }
    break
  }
  let cascade = word(tokens, i, "CASCADE")
  if cascade || word(tokens, i, "RESTRICT") {
    i += 1
  }
  if i != tokens.length() {
    return None
  }
  Some({ concurrent, cascade, count, })
}

///|
fn review_drop_index(
  spec : DropIndexSpec,
  state : Transaction,
  delivery : Delivery,
  implicit_batch : Bool,
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> Unit {
  if spec.concurrent {
    if state == Active || implicit_batch {
      finding(
        output,
        part,
        number,
        "PG206",
        Error,
        "DROP INDEX CONCURRENTLY cannot run in a transaction block.",
        "Submit the drop separately without an outer or multi-statement implicit transaction.",
      )
    } else if state == UnknownTransaction || delivery == UnknownDelivery {
      finding(
        output,
        part,
        number,
        "PG207",
        Error,
        "Concurrent-drop transaction compatibility is unknown.",
        "Supply the actual initial transaction state and submission mode.",
      )
    }
    if spec.count != 1 || spec.cascade {
      finding(
        output,
        part,
        number,
        "PG111",
        Error,
        "Concurrent index removal requires one name and forbids CASCADE.",
        "Review each index independently; inspect constraint dependencies before selecting a removal workflow.",
      )
    }
  } else {
    finding(
      output,
      part,
      number,
      "PG109",
      Warning,
      "Ordinary DROP INDEX takes an ACCESS EXCLUSIVE lock on the table.",
      "Assess the access-blocking window and lock budget; consider a supported concurrent drop.",
    )
  }
  if spec.cascade {
    finding(
      output,
      part,
      number,
      "PG112",
      Warning,
      "CASCADE may remove dependent objects along with the index.",
      "Inspect dependencies and explicitly review every dependent object before deployment.",
    )
  }
  finding(
    output,
    part,
    number,
    "PG110",
    Advisory,
    "Index ownership, dependencies, partition status and replacement coverage were not inspected.",
    "Inspect the target catalog and replacement index validity; CONCURRENTLY cannot remove constraint-backed or partitioned-table indexes.",
  )
}
