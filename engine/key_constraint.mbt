///|
priv struct KeyConstraintSpec {
  primary : Bool
  nulls_not_distinct : Bool
  deferrable : Bool
}

///|
fn key_constraint_spec(
  tokens : Array[@syntax.Token],
  start : Int32,
) -> KeyConstraintSpec? {
  if !word(tokens, start, "ADD") {
    return None
  }
  let mut i = start + 1
  if word(tokens, i, "CONSTRAINT") {
    if !short_identifier(tokens, i + 1) {
      return None
    }
    i += 2
  }
  let primary = word(tokens, i, "PRIMARY KEY") ||
    (word(tokens, i, "PRIMARY") && word(tokens, i + 1, "KEY"))
  if primary {
    i += if word(tokens, i, "PRIMARY KEY") { 1 } else { 2 }
  } else if word(tokens, i, "UNIQUE") {
    i += 1
  } else {
    return None
  }
  let mut nulls_not_distinct = false
  if !primary && word(tokens, i, "NULLS") {
    i += 1
    nulls_not_distinct = word(tokens, i, "NOT")
    if nulls_not_distinct {
      i += 1
    }
    if !word(tokens, i, "DISTINCT") {
      return None
    }
    i += 1
  }
  let (end, _) = match column_list(tokens, i) {
    Some(pair) => pair
    None => return None
  }
  i = end
  let deferrable = word(tokens, i, "DEFERRABLE")
  let nondeferrable = word(tokens, i, "NOT") &&
    word(tokens, i + 1, "DEFERRABLE")
  if deferrable {
    i += 1
  } else if nondeferrable {
    i += 2
  }
  let mut deferred = false
  if word(tokens, i, "INITIALLY") {
    deferred = word(tokens, i + 1, "DEFERRED")
    if (!deferred && !word(tokens, i + 1, "IMMEDIATE")) ||
      (deferred && nondeferrable) {
      return None
    }
    i += 2
  }
  if i != tokens.length() {
    return None
  }
  Some({ primary, nulls_not_distinct, deferrable: deferrable || deferred, })
}

///|
fn review_key_constraint(
  spec : KeyConstraintSpec,
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  finding(
    output,
    part,
    number,
    "PG425",
    Warning,
    "Adding a UNIQUE/PRIMARY KEY directly takes ACCESS EXCLUSIVE while building its supporting unique index.",
    "Inspect existing data and budget the blocking build; consider a separate CREATE UNIQUE INDEX CONCURRENTLY followed by a short USING INDEX cutover where PostgreSQL permits it.",
  )
  finding(
    output,
    part,
    number,
    "PG426",
    Warning,
    if spec.primary {
      "PRIMARY KEY addition also requires non-null keys; existing uniqueness, nullability and scan conditions are unverified."
    } else if spec.nulls_not_distinct {
      "UNIQUE NULLS NOT DISTINCT treats nulls as equal; old duplicate-null key groups can prevent the build."
    } else {
      "UNIQUE normally treats nulls as distinct; existing duplicate non-null keys can prevent the build."
    },
    "Check data using the exact constraint semantics, target types/collations, partition rules and existing constraint/index ownership. A CHECK or NOT VALID clause does not make a direct unique build concurrent.",
  )
  if spec.deferrable {
    finding(
      output,
      part,
      number,
      "PG427",
      Advisory,
      "Deferrable uniqueness changes failure timing and cannot serve as an ON CONFLICT arbiter; referenced-key eligibility also needs inspection.",
      "Review commit-time failures and callers using upsert or foreign keys before replacing an existing uniqueness contract.",
    )
  }
  if spec.primary {
    "add_primary_key"
  } else {
    "add_unique_constraint"
  }
}
