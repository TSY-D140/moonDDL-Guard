///|
priv struct ColumnAddition {
  action : ColumnAction
  part : Segment
}

///|
// Validate every action before producing findings or changing lock state.
fn combined_additions(part : Segment, start : Int32) -> Array[ColumnAddition]? {
  let tokens = part.tokens
  let ranges : Array[(Int32, Int32)] = []
  let mut depth = 0
  let mut first = start
  for i in start..<tokens.length() {
    match tokens[i].token_type {
      @syntax.L_PAREN => {
        depth += 1
        if depth > 32 {
          return None
        }
      }
      @syntax.R_PAREN => {
        depth -= 1
        if depth < 0 {
          return None
        }
      }
      @syntax.COMMA if depth == 0 => {
        if i == first || ranges.length() >= 31 {
          return None
        }
        ranges.push((first, i))
        first = i + 1
      }
      _ => ()
    }
  }
  if depth != 0 || first == tokens.length() || ranges.is_empty() {
    return None
  }
  ranges.push((first, tokens.length()))
  let offsets = source_offsets(part.sql)
  let names : Array[String] = []
  let additions : Array[ColumnAddition] = []
  for (begin, end) in ranges {
    if !word(tokens, begin, "ADD") {
      return None
    }
    let mut name = begin + 1
    if word(tokens, name, "COLUMN") {
      name += 1
    }
    if word(tokens, name, "IF") &&
      word(tokens, name + 1, "NOT") &&
      word(tokens, name + 2, "EXISTS") {
      name += 3
    }
    if name >= end ||
      !is_identifier(tokens[name]) ||
      tokens[name].text.is_empty() ||
      @utf8.encode(tokens[name].text).length() > 63 {
      return None
    }
    let key = constraint_table_key(tokens, name, name + 1)
    if names.contains(key) {
      return None
    }
    names.push(key)
    let local_start = offsets[tokens[begin].start - tokens[0].start]
    let local_end = offsets[tokens[end - 1].end + 1 - tokens[0].start]
    let relative = location_at(part.sql, local_start, local_end)
    let subset : Array[@syntax.Token] = []
    for i in begin..<end {
      subset.push(tokens[i])
    }
    let action_part : Segment = {
      tokens: subset,
      sql: part.sql[local_start:local_end].to_owned(),
      location: {
        start: part.location.start + local_start,
        end: part.location.start + local_end,
        line: part.location.line + relative.line - 1,
        column: if relative.line == 1 {
          part.location.column + relative.column - 1
        } else {
          relative.column
        },
      },
    }
    match column_action(action_part, 0) {
      Some(action) if action is AddColumn(_, _, _, _) =>
        additions.push({ action, part: action_part, })
      _ => return None
    }
  }
  Some(additions)
}

///|
fn review_additions(
  additions : Array[ColumnAddition],
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  finding(
    output,
    part,
    number,
    "PG501",
    Warning,
    "The combined statement takes ACCESS EXCLUSIVE on its target table until transaction end.",
    "Budget acquisition and the duration of the entire statement; all additions share the statement and transaction lock lifetime.",
  )
  let mut has_volatile = false
  let mut unknown_type = false
  for addition in additions {
    if addition.action is AddColumn(default, _, builtin, _) {
      if !builtin {
        unknown_type = true
      }
      if builtin && default is VolatileDefault {
        has_volatile = true
      }
    }
    ignore(
      review_column(addition.action, output, addition.part, number, lock=false),
    )
  }
  finding(
    output,
    part,
    number,
    "PG521",
    Advisory,
    if has_volatile {
      "An applicable volatile built-in default requires a rewrite; other fast-default additions do not make the whole statement metadata-only."
    } else if unknown_type {
      "Combined rewrite behavior is unresolved because at least one added type may be a constrained domain."
    } else {
      "These built-in absent/nonvolatile defaults do not themselves require a rewrite; NOT NULL validation and catalog conditions still need inspection."
    },
    "Scans and rewrites can be combined by PostgreSQL; do not sum per-column warnings as separate passes. Effects depend on actual creation, including individual IF NOT EXISTS no-ops; verify data and catalog conditions.",
  )
  "add_columns"
}
