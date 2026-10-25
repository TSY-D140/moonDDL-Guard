///|
priv enum ConstraintAction {
  AddCheck(Bool)
  Validate
  AttachIndex(Bool)
  Nullability(Bool)
}

///|
priv struct ConstraintSpec {
  table_key : String
  action : ConstraintAction
}

///|
fn constraint_table_key(
  tokens : Array[@syntax.Token],
  start : Int32,
  end : Int32,
) -> String {
  let names : Array[String] = []
  for i in start..<end {
    if tokens[i].token_type == @syntax.DOT {
      continue
    }
    let name = tokens[i].text
    let canonical = StringBuilder()
    for j in 0..<name.length() {
      let code = name.code_unit_at(j)
      let unit = name[j:j + 1].to_owned()
      canonical.write_string(
        if tokens[i].token_type != @syntax.IDENTIFIER &&
          code >= 65 &&
          code <= 90 {
          unit.to_lower()
        } else {
          unit
        },
      )
    }
    names.push(canonical.to_string())
  }
  Json(names).stringify()
}

///|
fn check_predicate_supported(
  part : Segment,
  start : Int32,
  end : Int32,
) -> Bool {
  if start >= end {
    return false
  }
  let offsets = source_offsets(part.sql)
  let first = part.tokens[0].start
  let text = part.sql[offsets[part.tokens[start].start - first]:offsets[part.tokens[end -
  1].end +
  1 -
  first]].to_owned()
  let ast = @sqlglot.parse_one("SELECT " + text, read="postgres") catch {
    _ => return false
  }
  if ast.kind != @syntax.Select || !has_only_keys(ast, ["expressions"]) {
    return false
  }
  let expressions = ast.list("expressions")
  expressions.length() == 1 && scalar_supported(expressions[0])
}

///|
fn constraint_spec(part : Segment) -> ConstraintSpec? {
  let tokens = part.tokens
  if tokens.length() > 256 ||
    !word(tokens, 0, "ALTER") ||
    !word(tokens, 1, "TABLE") {
    return None
  }
  let start = if word(tokens, 2, "ONLY") { 3 } else { 2 }
  let mut i = match qualified_name_end(tokens, start) {
    Some(end) => end
    None => return None
  }
  let table_key = constraint_table_key(tokens, start, i)
  if nullability_action(tokens, i) is Some(tightening) {
    return Some({ table_key, action: Nullability(tightening), })
  }
  if word(tokens, i, "VALIDATE") &&
    word(tokens, i + 1, "CONSTRAINT") &&
    i + 3 == tokens.length() &&
    is_identifier(tokens[i + 2]) &&
    !tokens[i + 2].text.is_empty() {
    return Some({ table_key, action: Validate, })
  }
  if word(tokens, i, "ADD") &&
    word(tokens, i + 1, "CONSTRAINT") &&
    i + 3 < tokens.length() &&
    is_identifier(tokens[i + 2]) &&
    !tokens[i + 2].text.is_empty() {
    let mut end = i + 3
    let merged_primary = tokens[end].token_type == @syntax.PRIMARY_KEY
    let primary = merged_primary ||
      (word(tokens, end, "PRIMARY") && word(tokens, end + 1, "KEY"))
    let unique = word(tokens, end, "UNIQUE")
    if merged_primary {
      end += 1
    } else if primary {
      end += 2
    } else if unique {
      end += 1
    }
    if (primary || unique) &&
      word(tokens, end, "USING") &&
      word(tokens, end + 1, "INDEX") &&
      end + 3 == tokens.length() &&
      is_identifier(tokens[end + 2]) &&
      !tokens[end + 2].text.is_empty() {
      return Some({ table_key, action: AttachIndex(primary), })
    }
  }
  if !word(tokens, i, "ADD") ||
    !word(tokens, i + 1, "CONSTRAINT") ||
    i + 4 >= tokens.length() ||
    !is_identifier(tokens[i + 2]) ||
    tokens[i + 2].text.is_empty() ||
    !word(tokens, i + 3, "CHECK") {
    return None
  }
  i += 4
  let end = match parenthesized_end(tokens, i) {
    Some(end) => end
    None => return None
  }
  if !check_predicate_supported(part, i + 1, end - 1) {
    return None
  }
  i = end
  let not_valid = word(tokens, i, "NOT") && word(tokens, i + 1, "VALID")
  if not_valid {
    i += 2
  }
  if i != tokens.length() {
    return None
  }
  Some({ table_key, action: AddCheck(not_valid), })
}

///|
fn review_constraint(
  spec : ConstraintSpec,
  held_tables : Map[String, Bool],
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  match spec.action {
    Nullability(tightening) => {
      held_tables[spec.table_key] = true
      review_nullability(tightening, output, part, number)
    }
    AttachIndex(primary) => {
      held_tables[spec.table_key] = true
      finding(
        output,
        part,
        number,
        "PG407",
        Warning,
        "Attaching an index-backed constraint takes ACCESS EXCLUSIVE until transaction end.",
        "Budget the cutover lock and commit promptly; concurrent index construction does not make the attachment lock-free.",
      )
      finding(
        output,
        part,
        number,
        "PG408",
        Advisory,
        "The existing index's eligibility and validity have not been inspected.",
        "Verify a valid eligible unique B-tree on this table, with default ordering, no predicate or expression keys, and no existing constraint ownership; partitioned tables are unsupported by PostgreSQL for this form.",
      )
      finding(
        output,
        part,
        number,
        "PG409",
        Advisory,
        "The constraint takes ownership of the index and can rename it; dropping the constraint also drops that index.",
        "Inspect dependencies and update cleanup/rollback plans before attaching; do not subsequently remove it as an independent index.",
      )
      if primary {
        finding(
          output,
          part,
          number,
          "PG410",
          Warning,
          "PRIMARY KEY attachment can need NOT NULL validation scans for nullable key columns.",
          "Inspect key-column nullability and existing data before cutover; do not assume a prebuilt unique index removes that scan.",
        )
      }
      if primary {
        "attach_primary_key"
      } else {
        "attach_unique_constraint"
      }
    }
    AddCheck(not_valid) => {
      held_tables[spec.table_key] = true
      finding(
        output,
        part,
        number,
        "PG401",
        Warning,
        "Adding a CHECK constraint acquires ACCESS EXCLUSIVE until transaction end.",
        "Use an intentional lock budget and commit promptly; NOT VALID skips the initial scan, not the strong lock.",
      )
      finding(
        output,
        part,
        number,
        if not_valid {
          "PG403"
        } else {
          "PG402"
        },
        if not_valid {
          Advisory
        } else {
          Warning
        },
        if not_valid {
          "NOT VALID checks subsequent writes but leaves existing rows unverified."
        } else {
          "Adding this validated CHECK can scan existing rows under the strong lock."
        },
        "Inspect data and expression semantics; consider NOT VALID followed by a separately committed VALIDATE CONSTRAINT.",
      )
      finding(
        output,
        part,
        number,
        "PG406",
        Advisory,
        "CHECK accepts both true and null; expression types and immutability were not verified.",
        "Use explicit IS NOT NULL where required; inspect operator/function resolution and existing data in the target database.",
      )
      if not_valid {
        "add_check_not_valid"
      } else {
        "add_check"
      }
    }
    Validate => {
      finding(
        output,
        part,
        number,
        "PG404",
        Advisory,
        "Constraint validation may scan existing rows with SHARE UPDATE EXCLUSIVE.",
        "Verify existence, enforcement, type and data; inspect inherited locks, table descendants and schema/search_path resolution. Validation is a no-op when already valid.",
      )
      if held_tables.contains(spec.table_key) {
        finding(
          output,
          part,
          number,
          "PG405",
          Warning,
          "An earlier assessed table change may retain ACCESS EXCLUSIVE during this validation.",
          "Commit the blocking phase before validation and submit phases separately; validation does not release an earlier stronger lock.",
        )
      }
      "validate_constraint"
    }
  }
}
