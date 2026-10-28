///|
priv struct ForeignKeySpec {
  referenced : String
  not_valid : Bool
  cascades : Bool
  sets_value : Bool
  deferred : Bool
}

///|
// Returns the first token after a nonempty, duplicate-free identifier list.
fn column_list(tokens : Array[@syntax.Token], start : Int32) -> (Int32, Int32)? {
  if start >= tokens.length() || tokens[start].token_type != @syntax.L_PAREN {
    return None
  }
  let seen : Map[String, Bool] = Map([])
  let mut i = start + 1
  for ;; {
    if i >= tokens.length() ||
      !is_identifier(tokens[i]) ||
      tokens[i].text.is_empty() ||
      @utf8.encode(tokens[i].text).length() > 63 {
      return None
    }
    let key = constraint_table_key(tokens, i, i + 1)
    if seen.contains(key) || seen.length() >= 32 {
      return None
    }
    seen[key] = true
    i += 1
    if i < tokens.length() && tokens[i].token_type == @syntax.COMMA {
      i += 1
      continue
    }
    if i >= tokens.length() || tokens[i].token_type != @syntax.R_PAREN {
      return None
    }
    return Some((i + 1, seen.length()))
  }
}

///|
fn foreign_key_spec(
  tokens : Array[@syntax.Token],
  start : Int32,
) -> ForeignKeySpec? {
  let mut i = start
  if !word(tokens, i, "FOREIGN KEY") {
    if !word(tokens, i, "FOREIGN") || !word(tokens, i + 1, "KEY") {
      return None
    }
    i += 2
  } else {
    i += 1
  }
  let (end, count) = match column_list(tokens, i) {
    Some(pair) => pair
    None => return None
  }
  i = end
  if !word(tokens, i, "REFERENCES") {
    return None
  }
  i += 1
  let referenced_start = i
  i = match tracked_relation_end(tokens, i) {
    Some(end) => end
    None => return None
  }
  let referenced = constraint_table_key(tokens, referenced_start, i)
  if i < tokens.length() && tokens[i].token_type == @syntax.L_PAREN {
    let (end, referenced_count) = match column_list(tokens, i) {
      Some(pair) => pair
      None => return None
    }
    if count != referenced_count {
      return None
    }
    i = end
  }
  if word(tokens, i, "MATCH") {
    if !word(tokens, i + 1, "SIMPLE") && !word(tokens, i + 1, "FULL") {
      return None
    }
    i += 2
  }
  let mut deleted = false
  let mut updated = false
  let mut cascades = false
  let mut sets_value = false
  while word(tokens, i, "ON") {
    if word(tokens, i + 1, "DELETE") && !deleted {
      deleted = true
    } else if word(tokens, i + 1, "UPDATE") && !updated {
      updated = true
    } else {
      return None
    }
    i += 2
    if word(tokens, i, "CASCADE") {
      cascades = true
      i += 1
    } else if word(tokens, i, "RESTRICT") {
      i += 1
    } else if word(tokens, i, "NO") && word(tokens, i + 1, "ACTION") {
      i += 2
    } else if word(tokens, i, "SET") &&
      (word(tokens, i + 1, "NULL") || word(tokens, i + 1, "DEFAULT")) {
      sets_value = true
      i += 2
    } else {
      return None
    }
  }
  let deferrable = word(tokens, i, "DEFERRABLE")
  let not_deferrable = word(tokens, i, "NOT") &&
    word(tokens, i + 1, "DEFERRABLE")
  if deferrable {
    i += 1
  } else if not_deferrable {
    i += 2
  }
  let mut deferred = false
  if word(tokens, i, "INITIALLY") {
    deferred = word(tokens, i + 1, "DEFERRED")
    if !deferred && !word(tokens, i + 1, "IMMEDIATE") {
      return None
    }
    if deferred && not_deferrable {
      return None
    }
    i += 2
  }
  let not_valid = word(tokens, i, "NOT") && word(tokens, i + 1, "VALID")
  if not_valid {
    i += 2
  }
  if i != tokens.length() {
    return None
  }
  Some({ referenced, not_valid, cascades, sets_value, deferred, })
}

///|
fn review_foreign_key(
  spec : ForeignKeySpec,
  table : String,
  held : Map[String, HeldTableLock],
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  // A later foreign key must never downgrade an earlier ACCESS EXCLUSIVE.
  for key in [table, spec.referenced] {
    if !held.contains(key) {
      held[key] = ShareRowExclusive
    }
  }
  finding(
    output,
    part,
    number,
    "PG415",
    Warning,
    "Adding a foreign key takes SHARE ROW EXCLUSIVE on both referencing and referenced tables until transaction end.",
    "Budget locks on both tables and commit the ADD phase promptly; NOT VALID does not remove these write-blocking locks.",
  )
  finding(
    output,
    part,
    number,
    if spec.not_valid {
      "PG417"
    } else {
      "PG416"
    },
    if spec.not_valid {
      Advisory
    } else {
      Warning
    },
    if spec.not_valid {
      "NOT VALID enforces subsequent foreign-key writes but leaves existing rows unverified."
    } else {
      "Adding a validated foreign key can scan existing referencing rows while both write-blocking locks are held."
    },
    "Check orphan rows with the actual MATCH/null semantics; consider NOT VALID, commit, then VALIDATE CONSTRAINT in a separate transaction.",
  )
  finding(
    output,
    part,
    number,
    "PG418",
    Advisory,
    "Referenced uniqueness, column types, privileges, partition rules and supporting indexes have not been inspected.",
    "Verify an eligible referenced key and matching columns. PostgreSQL does not automatically create an index on referencing columns; inspect delete/update lookup cost and catalog name resolution.",
  )
  if spec.cascades {
    finding(
      output,
      part,
      number,
      "PG419",
      Warning,
      "ON DELETE/UPDATE CASCADE can propagate future data changes to referencing rows.",
      "Review the referential action, affected data and downstream dependencies; this is distinct from DROP ... CASCADE.",
    )
  }
  if spec.sets_value || spec.deferred {
    finding(
      output,
      part,
      number,
      "PG420",
      Advisory,
      "Foreign-key action/default/nullability or deferred-check behavior needs application and catalog validation.",
      "SET NULL/DEFAULT can conflict with column constraints or the referenced key; deferred failures may occur at transaction commit rather than at the original write.",
    )
  }
  if spec.not_valid {
    "add_foreign_key_not_valid"
  } else {
    "add_foreign_key"
  }
}
