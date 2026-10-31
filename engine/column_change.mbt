///|
priv enum DefaultKind {
  NoDefault
  ConstantDefault
  StableDefault
  VolatileDefault
}

///|
priv enum ColumnAction {
  AddColumn(DefaultKind, Bool, Bool, Bool) // default, NOT NULL, builtin type, IF NOT EXISTS
  ChangeType(Bool) // USING present; old type is intentionally unknown
  ChangeDefault(Bool) // set rather than drop
  AddGeneratedColumn(GeneratedColumnSpec)
  ChangeGeneration(GenerationChange)
}

///|
// Bounded decimal typemods; no exponent, hex, signs except numeric scale.
fn type_integer(
  tokens : Array[@syntax.Token],
  start : Int32,
) -> (Int32, Int32)? {
  let negative = start < tokens.length() &&
    tokens[start].token_type == @syntax.DASH
  let i = if negative { start + 1 } else { start }
  if i >= tokens.length() || tokens[i].token_type != @syntax.NUMBER {
    return None
  }
  let text = tokens[i].text
  if text.is_empty() || text.length() > 4 {
    return None
  }
  let mut n = 0
  for ch in text {
    let c = ch.to_int()
    if c < 48 || c > 57 {
      return None
    }
    n = n * 10 + c - 48
  }
  Some((i + 1, if negative { -n } else { n }))
}

///|
fn column_type(tokens : Array[@syntax.Token], start : Int32) -> (Int32, Bool)? {
  if start >= tokens.length() {
    return None
  }
  let mut i = start
  // Schema-qualified/custom names are assessed conservatively as possible domains.
  if is_identifier(tokens[i]) &&
    i + 1 < tokens.length() &&
    tokens[i + 1].token_type == @syntax.DOT {
    return qualified_name_end(tokens, i).map(end => (end, false))
  }
  let kind = tokens[i].text.to_upper()
  if tokens[i].token_type == @syntax.IDENTIFIER {
    return if tokens[i].text.is_empty() { None } else { Some((i + 1, false)) }
  }
  let simple = [
    "SMALLINT", "INT2", "INTEGER", "INT", "INT4", "BIGINT", "INT8", "BOOLEAN", "BOOL",
    "TEXT", "UUID", "JSON", "JSONB", "BYTEA", "DATE", "REAL", "FLOAT4", "FLOAT8",
  ].contains(kind)
  let character = ["VARCHAR", "CHAR", "CHARACTER", "CHARACTER VARYING"].contains(
    kind,
  )
  let numeric = kind == "NUMERIC" || kind == "DECIMAL"
  let temporal = ["TIMESTAMP", "TIMESTAMPTZ", "TIME", "TIMETZ"].contains(kind)
  if !simple &&
    !character &&
    !numeric &&
    !temporal &&
    !word(tokens, i, "DOUBLE") &&
    !word(tokens, i, "DOUBLE PRECISION") {
    return if is_identifier(tokens[i]) { Some((i + 1, false)) } else { None }
  }
  i += 1
  if kind == "DOUBLE" {
    if !word(tokens, i, "PRECISION") {
      return None
    }
    i += 1
  }
  if kind == "CHARACTER" && word(tokens, i, "VARYING") {
    i += 1
  }
  if i < tokens.length() && tokens[i].token_type == @syntax.L_PAREN {
    if simple || kind == "DOUBLE" || kind == "DOUBLE PRECISION" {
      return None
    }
    let (end, first) = match type_integer(tokens, i + 1) {
      Some(pair) => pair
      None => return None
    }
    i = end
    if (character && (first <= 0 || first > 9999)) ||
      (numeric && (first < 1 || first > 1000)) ||
      (temporal && (first < 0 || first > 6)) {
      return None
    }
    if numeric && i < tokens.length() && tokens[i].token_type == @syntax.COMMA {
      let (end, scale) = match type_integer(tokens, i + 1) {
        Some(pair) => pair
        None => return None
      }
      if scale < -1000 || scale > 1000 {
        return None
      }
      i = end
    }
    if i >= tokens.length() || tokens[i].token_type != @syntax.R_PAREN {
      return None
    }
    i += 1
  }
  if (kind == "TIMESTAMP" || kind == "TIME") &&
    (word(tokens, i, "WITH") || word(tokens, i, "WITHOUT")) {
    if !word(tokens, i + 1, "TIME ZONE") {
      if !word(tokens, i + 1, "TIME") || !word(tokens, i + 2, "ZONE") {
        return None
      }
      i += 3
    } else {
      i += 2
    }
  }
  Some((i, true))
}

///|
fn default_kind(
  tokens : Array[@syntax.Token],
  start : Int32,
  end : Int32,
) -> DefaultKind? {
  if start >= end {
    return None
  }
  if tokens[start].token_type == @syntax.L_PAREN &&
    parenthesized_end(tokens, start) == Some(end) {
    return default_kind(tokens, start + 1, end - 1)
  }
  if start + 1 == end &&
    (
      tokens[start].token_type == @syntax.STRING ||
      tokens[start].token_type == @syntax.NUMBER ||
      word(tokens, start, "TRUE") ||
      word(tokens, start, "FALSE") ||
      word(tokens, start, "NULL")
    ) {
    return Some(ConstantDefault)
  }
  if start + 2 == end &&
    (
      tokens[start].token_type == @syntax.DASH ||
      tokens[start].token_type == @syntax.PLUS
    ) &&
    tokens[start + 1].token_type == @syntax.NUMBER {
    return Some(ConstantDefault)
  }
  if word(tokens, start, "CURRENT_TIMESTAMP") && start + 1 == end {
    return Some(StableDefault)
  }
  let name = tokens[start].text.to_upper()
  if [
      "NOW", "TRANSACTION_TIMESTAMP", "STATEMENT_TIMESTAMP", "CLOCK_TIMESTAMP", "RANDOM",
      "GEN_RANDOM_UUID", "UUIDV4", "UUIDV7",
    ].contains(name) &&
    word(tokens, start, name) &&
    start + 3 == end &&
    tokens[start + 1].token_type == @syntax.L_PAREN &&
    tokens[start + 2].token_type == @syntax.R_PAREN {
    return Some(
      if ["CLOCK_TIMESTAMP", "RANDOM", "GEN_RANDOM_UUID", "UUIDV4", "UUIDV7"].contains(
          name,
        ) {
        VolatileDefault
      } else {
        StableDefault
      },
    )
  }
  if word(tokens, start, "NEXTVAL") &&
    start + 4 == end &&
    tokens[start + 1].token_type == @syntax.L_PAREN &&
    tokens[start + 2].token_type == @syntax.STRING &&
    tokens[start + 3].token_type == @syntax.R_PAREN {
    return Some(VolatileDefault)
  }
  None
}

///|
fn conversion_supported(part : Segment, start : Int32, end : Int32) -> Bool {
  let tokens = part.tokens
  if start >= end {
    return false
  }
  if tokens[start].token_type == @syntax.L_PAREN &&
    parenthesized_end(tokens, start) == Some(end) {
    return conversion_supported(part, start + 1, end - 1)
  }
  let mut depth = 0
  for i in start..<end {
    if tokens[i].token_type == @syntax.L_PAREN {
      depth += 1
    }
    if depth > 32 {
      return false
    }
    if tokens[i].token_type == @syntax.R_PAREN {
      depth -= 1
    }
    if depth == 0 && tokens[i].token_type == @syntax.DCOLON {
      return check_predicate_supported(part, start, i) &&
        column_type(tokens, i + 1).map(pair => pair.0 == end).unwrap_or(false)
    }
  }
  check_predicate_supported(part, start, end)
}

///|
fn column_action(part : Segment, start : Int32) -> ColumnAction? {
  let tokens = part.tokens
  let mut i = start + 1
  if word(tokens, start, "ADD") {
    if word(tokens, i, "COLUMN") {
      i += 1
    }
    let exists = word(tokens, i, "IF") &&
      word(tokens, i + 1, "NOT") &&
      word(tokens, i + 2, "EXISTS")
    if exists {
      i += 3
    }
    if i >= tokens.length() ||
      !is_identifier(tokens[i]) ||
      tokens[i].text.is_empty() {
      return None
    }
    i += 1
    if word(tokens, i, "SERIAL") ||
      word(tokens, i, "BIGSERIAL") ||
      word(tokens, i, "SMALLSERIAL") {
      if i + 1 != column_suffix_end(tokens) {
        return None
      }
      return Some(
        AddGeneratedColumn({ kind: SerialColumn, exists, not_null: true, }),
      )
    }
    let integer = [
        "SMALLINT", "INT2", "INTEGER", "INT", "INT4", "BIGINT", "INT8",
      ]
      .iter()
      .any(name => word(tokens, i, name))
    let (end, builtin) = match column_type(tokens, i) {
      Some(pair) => pair
      None => return None
    }
    i = end
    if generated_column(part, i, integer, builtin, exists) is Some(spec) {
      return Some(AddGeneratedColumn(spec))
    }
    let leading_nonnull = word(tokens, i, "NOT NULL") ||
      (word(tokens, i, "NOT") && word(tokens, i + 1, "NULL"))
    if leading_nonnull {
      i += if word(tokens, i, "NOT NULL") { 1 } else { 2 }
    }
    let mut last = tokens.length()
    let trailing_nonnull = last > i &&
      (
        word(tokens, last - 1, "NOT NULL") ||
        (
          last >= 2 &&
          word(tokens, last - 2, "NOT") &&
          word(tokens, last - 1, "NULL")
        )
      )
    if trailing_nonnull && last > i {
      last -= if word(tokens, last - 1, "NOT NULL") { 1 } else { 2 }
    }
    if leading_nonnull && trailing_nonnull && last >= i {
      return None
    }
    let default = if i == last {
      NoDefault
    } else {
      if !word(tokens, i, "DEFAULT") {
        return None
      }
      match default_kind(tokens, i + 1, last) {
        Some(kind) => kind
        None => return None
      }
    }
    return Some(
      AddColumn(default, leading_nonnull || trailing_nonnull, builtin, exists),
    )
  }
  if !word(tokens, start, "ALTER") {
    return None
  }
  if word(tokens, i, "COLUMN") {
    i += 1
  }
  if i >= tokens.length() ||
    !is_identifier(tokens[i]) ||
    tokens[i].text.is_empty() {
    return None
  }
  i += 1
  if generation_change(part, i) is Some(change) {
    return Some(ChangeGeneration(change))
  }
  if word(tokens, i, "DROP") &&
    word(tokens, i + 1, "DEFAULT") &&
    i + 2 == tokens.length() {
    return Some(ChangeDefault(false))
  }
  if word(tokens, i, "SET") && word(tokens, i + 1, "DEFAULT") {
    return default_kind(tokens, i + 2, tokens.length()).map(_ => {
      ChangeDefault(true)
    })
  }
  if word(tokens, i, "SET") && word(tokens, i + 1, "DATA") {
    i += 2
  }
  if !word(tokens, i, "TYPE") {
    return None
  }
  i += 1
  let (end, _) = match column_type(tokens, i) {
    Some(pair) => pair
    None => return None
  }
  i = end
  let has_conversion = word(tokens, i, "USING")
  if has_conversion {
    if !conversion_supported(part, i + 1, tokens.length()) {
      return None
    }
  } else if i != tokens.length() {
    return None
  }
  Some(ChangeType(has_conversion))
}

///|
fn review_column(
  action : ColumnAction,
  output : Array[Finding],
  part : Segment,
  number : Int32,
  lock~ : Bool = true,
) -> String {
  if lock {
    finding(
      output,
      part,
      number,
      "PG501",
      Warning,
      "This column change takes ACCESS EXCLUSIVE until transaction end.",
      "Budget lock acquisition and operation duration; a metadata-only change can still wait for and retain a strong lock.",
    )
  }
  match action {
    AddGeneratedColumn(spec) =>
      review_generated_column(spec, output, part, number)
    ChangeGeneration(change) =>
      review_generation_change(change, output, part, number)
    AddColumn(default, not_null, builtin, exists) => {
      if !builtin {
        finding(
          output,
          part,
          number,
          "PG504",
          Warning,
          "The added column's type is not a verified built-in; constrained domains or custom coercions can require a rewrite.",
          "Inspect the resolved type, domain constraints and coercion functions in the target database; no no-rewrite claim is made.",
        )
      } else {
        match default {
          VolatileDefault =>
            finding(
              output,
              part,
              number,
              "PG503",
              Warning,
              "Under standard built-in resolution, this volatile default requires per-row evaluation and a table/index rewrite.",
              "Budget disk, WAL, lock duration and old-snapshot effects; consider adding a nullable column, backfilling separately, then setting the future default.",
            )
          NoDefault | ConstantDefault | StableDefault =>
            finding(
              output,
              part,
              number,
              "PG502",
              Advisory,
              "Under standard built-in resolution, this absent or nonvolatile default does not itself require a table rewrite.",
              "Verify resolved type/function identities, constraints and descendants; no-rewrite does not mean lock-free or universally safe.",
            )
        }
      }
      if default is StableDefault {
        finding(
          output,
          part,
          number,
          "PG505",
          Advisory,
          "A stable default is evaluated for the statement; existing rows receive that result rather than a separately computed value per row.",
          "Confirm timestamp/backfill semantics; future inserts evaluate their own defaults.",
        )
      }
      if not_null {
        finding(
          output,
          part,
          number,
          "PG506",
          Warning,
          "The new NOT NULL requirement can reject existing rows or default results and may need validation.",
          "Verify existing-row and default nullability; adding NOT NULL without a non-null default fails on a nonempty table. A scan is distinct from a rewrite.",
        )
      }
      finding(
        output,
        part,
        number,
        "PG507",
        Advisory,
        "Actual type/function resolution, table kind, descendants and stored data have not been inspected.",
        "Verify catalog preconditions and deployment behavior; unknown default expressions, arrays and unassessed clauses remain outside this profile. Generation changes have a separate bounded assessment.",
      )
      if exists {
        finding(
          output,
          part,
          number,
          "PG508",
          Advisory,
          "IF NOT EXISTS does not verify an existing column's type, default or constraints.",
          "Inspect the existing definition; the command can be a no-op, so reported effects are conditional on adding the column.",
        )
      }
      "add_column"
    }
    ChangeType(has_conversion) => {
      finding(
        output,
        part,
        number,
        "PG509",
        Warning,
        "Column type changes normally rewrite the table and may rebuild indexes; the old type and binary-coercion exception are unknown.",
        "Inspect old/new type, USING semantics, indexes, collation, disk/WAL and snapshot effects; do not assume widening or text/varchar changes require or avoid a rewrite without catalog evidence.",
      )
      finding(
        output,
        part,
        number,
        "PG510",
        Warning,
        if has_conversion {
          "USING can change or lose stored values and is not applied to the existing default expression."
        } else {
          "Without USING, existing rows and the column default need a valid assignment conversion; data can fail or lose precision."
        },
        "Validate conversion against representative data and constraints; consider a new-column/backfill/cutover workflow. Review defaults separately before changing the type.",
      )
      finding(
        output,
        part,
        number,
        "PG511",
        Advisory,
        "Type changes affect column statistics and can fail on dependent objects or descendant-table requirements.",
        "Inspect views, constraints, indexes, defaults and descendants; plan ANALYZE where applicable. SQL text alone cannot prove conversion correctness.",
      )
      "alter_column_type"
    }
    ChangeDefault(setting) => {
      finding(
        output,
        part,
        number,
        "PG512",
        Advisory,
        "Changing a column default affects subsequent writes; it does not backfill existing rows or itself rewrite their data.",
        "Review future inserts and column constraints; use a separate, bounded data backfill where existing rows must change.",
      )
      if setting {
        "set_column_default"
      } else {
        "drop_column_default"
      }
    }
  }
}
