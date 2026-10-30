///|
priv struct CreateTableSpec {
  exists : Bool
  temporary : Bool
  unlogged : Bool
  foreign_keys : Array[ForeignKeySpec]
}

///|
fn segment_text(part : Segment, start : Int32, end : Int32) -> String {
  if start >= end {
    return ""
  }
  let offsets = source_offsets(part.sql)
  let first = part.tokens[0].start
  part.sql[offsets[part.tokens[start].start - first]:offsets[part.tokens[end - 1].end +
  1 -
  first]].to_owned()
}

///|
// Internal grammar reuse only. No rewritten SQL is returned or executed.
fn table_element(text : String) -> ConstraintAction? {
  let parts = segments("ALTER TABLE __guard ADD " + text) catch {
    _ => return None
  }
  if parts.length() != 1 {
    return None
  }
  constraint_spec(parts[0]).map(spec => spec.action)
}

///|
fn create_element(text : String, foreign_keys : Array[ForeignKeySpec]) -> Bool {
  let parts = segments(text) catch { _ => return false }
  if parts.length() != 1 {
    return false
  }
  let part = parts[0]
  let tokens = part.tokens
  let table_constraint = word(tokens, 0, "CONSTRAINT") ||
    word(tokens, 0, "PRIMARY KEY") ||
    word(tokens, 0, "PRIMARY") ||
    word(tokens, 0, "UNIQUE") ||
    word(tokens, 0, "FOREIGN KEY") ||
    word(tokens, 0, "FOREIGN") ||
    word(tokens, 0, "CHECK")
  let constraint_text = if table_constraint {
    if word(tokens, 0, "CHECK") {
      "CONSTRAINT __guard_check " + text
    } else {
      text
    }
  } else {
    if !short_identifier(tokens, 0) {
      return false
    }
    let mut depth = 0
    let mut split = tokens.length()
    for i in 1..<tokens.length() {
      if tokens[i].token_type == @syntax.L_PAREN {
        depth += 1
      }
      if tokens[i].token_type == @syntax.R_PAREN {
        depth -= 1
      }
      if depth == 0 &&
        (
          word(tokens, i, "CONSTRAINT") ||
          word(tokens, i, "PRIMARY KEY") ||
          word(tokens, i, "PRIMARY") ||
          word(tokens, i, "UNIQUE") ||
          word(tokens, i, "REFERENCES") ||
          word(tokens, i, "CHECK")
        ) {
        split = i
        break
      }
    }
    let base = segment_text(part, 0, split)
    match table_element(base) {
      Some(ColumnChange(AddColumn(_, _, _, _)))
      | Some(ColumnChange(AddGeneratedColumn(_))) => ()
      _ => return false
    }
    if split == tokens.length() {
      return true
    }
    let mut i = split
    let prefix = if word(tokens, i, "CONSTRAINT") {
      if !short_identifier(tokens, i + 1) {
        return false
      }
      i += 2
      segment_text(part, split, i) + " "
    } else {
      ""
    }
    let column = segment_text(part, 0, 1)
    if word(tokens, i, "REFERENCES") {
      prefix +
      "FOREIGN KEY (" +
      column +
      ") " +
      segment_text(part, i, tokens.length())
    } else if word(tokens, i, "CHECK") {
      (if prefix == "" { "CONSTRAINT __guard_check " } else { prefix }) +
      segment_text(part, i, tokens.length())
    } else {
      let head = i
      if word(tokens, i, "PRIMARY KEY") {
        i += 1
      } else if word(tokens, i, "PRIMARY") && word(tokens, i + 1, "KEY") {
        i += 2
      } else if word(tokens, i, "UNIQUE") {
        i += 1
        if word(tokens, i, "NULLS") {
          i += 1
          if word(tokens, i, "NOT") {
            i += 1
          }
          if !word(tokens, i, "DISTINCT") {
            return false
          }
          i += 1
        }
      } else {
        return false
      }
      prefix +
      segment_text(part, head, i) +
      " (" +
      column +
      ") " +
      segment_text(part, i, tokens.length())
    }
  }
  match table_element(constraint_text) {
    Some(DirectKey(_)) | Some(AddCheck(false)) => true
    Some(ForeignKey(spec)) if !spec.not_valid => {
      foreign_keys.push(spec)
      true
    }
    _ => false
  }
}

///|
fn create_table_spec(part : Segment) -> CreateTableSpec? {
  let tokens = part.tokens
  if tokens.length() > 1024 || !word(tokens, 0, "CREATE") {
    return None
  }
  let temporary = word(tokens, 1, "TEMP") || word(tokens, 1, "TEMPORARY")
  let unlogged = word(tokens, 1, "UNLOGGED")
  let mut i = if temporary || unlogged { 2 } else { 1 }
  if !word(tokens, i, "TABLE") {
    return None
  }
  i += 1
  let exists = word(tokens, i, "IF") &&
    word(tokens, i + 1, "NOT") &&
    word(tokens, i + 2, "EXISTS")
  if exists {
    i += 3
  }
  i = match tracked_relation_end(tokens, i) {
    Some(end) => end
    None => return None
  }
  let body_start = i + 1
  let end = match parenthesized_end(tokens, i) {
    Some(end) => end
    None => return None
  }
  if end != tokens.length() {
    return None
  }
  let foreign_keys : Array[ForeignKeySpec] = []
  let mut start = body_start
  let mut depth = 0
  let mut definitions = 0
  let columns : Map[String, Bool] = Map([])
  for j in body_start..<end {
    let delimiter = j == end - 1 ||
      (depth == 0 && tokens[j].token_type == @syntax.COMMA)
    if delimiter {
      if start == j {
        if start == body_start && j == end - 1 {
          break
        }
        return None
      }
      if short_identifier(tokens, start) && !word(tokens, start, "CONSTRAINT") {
        let key = constraint_table_key(tokens, start, start + 1)
        if columns.contains(key) {
          return None
        }
        columns[key] = true
      }
      definitions += 1
      if definitions > 128 ||
        !create_element(segment_text(part, start, j), foreign_keys) {
        return None
      }
      start = j + 1
    } else {
      if tokens[j].token_type == @syntax.L_PAREN {
        depth += 1
      }
      if tokens[j].token_type == @syntax.R_PAREN {
        depth -= 1
      }
    }
  }
  Some({ exists, temporary, unlogged, foreign_keys, })
}

///|
fn review_create_table(
  spec : CreateTableSpec,
  held : Map[String, HeldTableLock],
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  finding(
    output,
    part,
    number,
    "PG911",
    Advisory,
    "CREATE TABLE defines a new relation; existing-table rewrite/build warnings are not inferred for its new columns or keys.",
    "Verify schema/name privileges, type/default/generated-expression resolution, constraints and storage requirements. This review does not inspect or publish a schema model.",
  )
  if spec.exists {
    finding(
      output,
      part,
      number,
      "PG912",
      Warning,
      "CREATE TABLE IF NOT EXISTS does not verify an existing table's columns, constraints or generation definitions.",
      "Compare the actual existing schema before relying on this as an idempotent migration.",
    )
  }
  if spec.unlogged || spec.temporary {
    finding(
      output,
      part,
      number,
      "PG913",
      Warning,
      if spec.unlogged {
        "UNLOGGED table data is not crash-safe or replicated to standby servers."
      } else {
        "Temporary tables have session-specific visibility/lifetime; migration pools and persistent objects cannot assume a shared table."
      },
      "Confirm persistence, crash/restart and connection/session requirements before selecting this table kind.",
    )
  }
  for key in spec.foreign_keys {
    if !held.contains(key.referenced) {
      held[key.referenced] = ShareRowExclusive
    }
    finding(
      output,
      part,
      number,
      "PG914",
      Warning,
      "Creating a foreign key can take SHARE ROW EXCLUSIVE on the referenced relation; existing target rows/types/key eligibility are unverified.",
      "Budget the referenced-table lock and inspect its eligible key, data types, privileges and partition rules. A new child table does not mean the referenced existing table is unaffected.",
    )
    if key.cascades {
      finding(
        output,
        part,
        number,
        "PG419",
        Warning,
        "The new table's referential action can cascade future updates/deletes to child rows.",
        "Review referential actions, indexes and downstream data-loss implications before deployment.",
      )
    }
  }
  "create_table"
}
