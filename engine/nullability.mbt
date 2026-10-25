///|
fn nullability_action(tokens : Array[@syntax.Token], start : Int32) -> Bool? {
  if !word(tokens, start, "ALTER") {
    return None
  }
  let mut i = start + 1
  if word(tokens, i, "COLUMN") {
    i += 1
  }
  if i >= tokens.length() ||
    !is_identifier(tokens[i]) ||
    tokens[i].text.is_empty() {
    return None
  }
  i += 1
  let tightening = word(tokens, i, "SET")
  if !tightening && !word(tokens, i, "DROP") {
    return None
  }
  if (
      i + 3 == tokens.length() &&
      word(tokens, i + 1, "NOT") &&
      word(tokens, i + 2, "NULL")
    ) ||
    (i + 2 == tokens.length() && word(tokens, i + 1, "NOT NULL")) {
    Some(tightening)
  } else {
    None
  }
}

///|
fn review_nullability(
  tightening : Bool,
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  finding(
    output,
    part,
    number,
    "PG411",
    Warning,
    "Changing column nullability acquires ACCESS EXCLUSIVE until transaction end.",
    "Budget lock acquisition and the full operation; separate long validation work from the final metadata change where supported.",
  )
  if tightening {
    finding(
      output,
      part,
      number,
      "PG412",
      Warning,
      "SET NOT NULL can scan existing rows while holding the strong lock.",
      "Check for nulls and inspect a valid retained CHECK proving non-nullness; that proof can avoid a scan, but no catalog proof has been verified here.",
    )
  } else {
    finding(
      output,
      part,
      number,
      "PG413",
      Warning,
      "Successful DROP NOT NULL removes this column's NOT NULL requirement; other constraints may still reject nulls.",
      "Review downstream readers and future writes; re-adding NOT NULL may require cleaning data written after this change.",
    )
  }
  finding(
    output,
    part,
    number,
    "PG414",
    Advisory,
    "Column metadata, data, primary-key dependencies and table ancestry were not inspected.",
    "Verify the target schema and data; parent/partition requirements or primary-key constraints can prevent dropping NOT NULL. Do not infer no-scan eligibility merely from earlier SQL text.",
  )
  if tightening {
    "set_not_null"
  } else {
    "drop_not_null"
  }
}
