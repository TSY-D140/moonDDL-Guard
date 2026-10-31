///|
priv enum GeneratedKind {
  IdentityColumn(Bool)
  SerialColumn
  ComputedColumn(Bool)
}

///|
priv struct GeneratedColumnSpec {
  kind : GeneratedKind
  exists : Bool
  not_null : Bool
}

///|
priv enum GenerationChange {
  AttachIdentity(Bool)
  SetIdentityMode(Bool)
  RemoveIdentity
  ReplaceGeneratedExpression
  RemoveGeneratedExpression
}

///|
fn column_suffix_end(tokens : Array[@syntax.Token]) -> Int32 {
  let n = tokens.length()
  if n > 0 && word(tokens, n - 1, "NOT NULL") {
    n - 1
  } else if n > 1 && word(tokens, n - 2, "NOT") && word(tokens, n - 1, "NULL") {
    n - 2
  } else {
    n
  }
}

///|
fn identity_mode(
  tokens : Array[@syntax.Token],
  start : Int32,
) -> (Int32, Bool)? {
  if word(tokens, start, "ALWAYS") {
    Some((start + 1, true))
  } else if word(tokens, start, "BY") && word(tokens, start + 1, "DEFAULT") {
    Some((start + 2, false))
  } else {
    None
  }
}

///|
fn generated_column(
  part : Segment,
  start : Int32,
  integer : Bool,
  builtin : Bool,
  exists : Bool,
) -> GeneratedColumnSpec? {
  let tokens = part.tokens
  if !word(tokens, start, "GENERATED") {
    return None
  }
  let (mode_end, always) = match identity_mode(tokens, start + 1) {
    Some(pair) => pair
    None => return None
  }
  let mut i = mode_end
  if !word(tokens, i, "AS") {
    return None
  }
  i += 1
  let last = column_suffix_end(tokens)
  if word(tokens, i, "IDENTITY") {
    if !integer || i + 1 != last {
      return None
    }
    return Some({ kind: IdentityColumn(always), exists, not_null: true, })
  }
  if !always {
    return None
  }
  let end = match parenthesized_end(tokens, i) {
    Some(end) => end
    None => return None
  }
  if !conversion_supported(part, i + 1, end - 1) {
    return None
  }
  i = end
  let stored = word(tokens, i, "STORED")
  if stored || word(tokens, i, "VIRTUAL") {
    i += 1
  }
  if i != last || (!stored && !builtin) {
    return None
  }
  Some({
    kind: ComputedColumn(stored),
    exists,
    not_null: last != tokens.length(),
  })
}

///|
fn generation_change(part : Segment, start : Int32) -> GenerationChange? {
  let tokens = part.tokens
  let n = tokens.length()
  if (word(tokens, start, "ADD") || word(tokens, start, "SET")) &&
    word(tokens, start + 1, "GENERATED") {
    let (mode_end, always) = match identity_mode(tokens, start + 2) {
      Some(pair) => pair
      None => return None
    }
    let mut end = mode_end
    let attaching = word(tokens, start, "ADD")
    if attaching {
      if !word(tokens, end, "AS") || !word(tokens, end + 1, "IDENTITY") {
        return None
      }
      end += 2
    }
    if end != n {
      return None
    }
    return Some(
      if attaching {
        AttachIdentity(always)
      } else {
        SetIdentityMode(always)
      },
    )
  }
  if word(tokens, start, "DROP") &&
    (
      word(tokens, start + 1, "IDENTITY") ||
      word(tokens, start + 1, "EXPRESSION")
    ) {
    let end = if word(tokens, start + 2, "IF") &&
      word(tokens, start + 3, "EXISTS") {
      start + 4
    } else {
      start + 2
    }
    if end != n {
      return None
    }
    return Some(
      if word(tokens, start + 1, "IDENTITY") {
        RemoveIdentity
      } else {
        RemoveGeneratedExpression
      },
    )
  }
  if word(tokens, start, "SET") &&
    word(tokens, start + 1, "EXPRESSION") &&
    word(tokens, start + 2, "AS") {
    let end = match parenthesized_end(tokens, start + 3) {
      Some(end) => end
      None => return None
    }
    if end != n || !conversion_supported(part, start + 4, end - 1) {
      return None
    }
    return Some(ReplaceGeneratedExpression)
  }
  None
}

///|
fn review_generated_column(
  spec : GeneratedColumnSpec,
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  if spec.not_null && spec.kind is ComputedColumn(_) {
    finding(
      output,
      part,
      number,
      "PG520",
      Warning,
      "A generated column with NOT NULL must validate existing generated results; a virtual column can require an old-row scan without a table rewrite.",
      "Check null-producing inputs and expression failures on existing rows; budget the scan under ACCESS EXCLUSIVE. Virtual storage alone does not make this metadata-only.",
    )
  }
  let operation = match spec.kind {
    ComputedColumn(stored) => {
      finding(
        output,
        part,
        number,
        if stored {
          "PG514"
        } else {
          "PG516"
        },
        if stored {
          Warning
        } else {
          Advisory
        },
        if stored {
          "Adding a stored generated column computes old-row values and rewrites the table/indexes under the strong lock."
        } else {
          "A PostgreSQL 18 virtual generated column is computed on reads and does not itself require a table rewrite; the strong lock still applies."
        },
        "Inspect immutable expression/operator resolution, referenced columns and types. Virtual generation requires built-in types/functions and does not allow references to other generated columns.",
      )
      if stored {
        "add_stored_generated_column"
      } else {
        "add_virtual_generated_column"
      }
    }
    IdentityColumn(always) => {
      finding(
        output,
        part,
        number,
        "PG514",
        Warning,
        "Adding an identity column to an existing table assigns sequence values and rewrites the table/indexes.",
        "Budget the full locked rewrite and verify generated values, privileges and sequence ownership; consider a separate table/backfill cutover for large tables.",
      )
      finding(
        output,
        part,
        number,
        "PG515",
        Advisory,
        if always {
          "GENERATED ALWAYS rejects ordinary explicit identity values; identity is NOT NULL but does not itself guarantee uniqueness."
        } else {
          "GENERATED BY DEFAULT permits explicit values that may diverge from the sequence; identity does not itself guarantee uniqueness."
        },
        "Review callers, key constraints, sequence state and failure/retry behavior; inspect the target table kind and data.",
      )
      "add_identity_column"
    }
    SerialColumn => {
      finding(
        output,
        part,
        number,
        "PG514",
        Warning,
        "Adding a serial column introduces a volatile sequence default and a locked table/index rewrite.",
        "Inspect sequence ownership, privileges and old-row assignments; consider identity for new definitions and a separate backfill/cutover workflow for large tables.",
      )
      finding(
        output,
        part,
        number,
        "PG515",
        Advisory,
        "Serial creates an owned sequence/default and NOT NULL; it is not a uniqueness or gap-free ordering guarantee.",
        "Verify primary/unique constraints, manual inserts and sequence synchronization before use.",
      )
      "add_serial_column"
    }
  }
  if spec.exists {
    finding(
      output,
      part,
      number,
      "PG508",
      Advisory,
      "IF NOT EXISTS does not verify an existing column's generation or sequence definition.",
      "Inspect the actual definition; the change can be a no-op and the described effects are conditional on creation.",
    )
  }
  operation
}

///|
fn review_generation_change(
  change : GenerationChange,
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  match change {
    AttachIdentity(always) | SetIdentityMode(always) => {
      finding(
        output,
        part,
        number,
        "PG517",
        Warning,
        if always {
          "Changing an existing column to ALWAYS identity changes future explicit-write acceptance; existing rows are not assigned new values."
        } else {
          "Changing an existing column to BY DEFAULT identity permits explicit future values; existing rows are not backfilled."
        },
        "Inspect integer type, NOT NULL metadata, current defaults/identity state and sequence synchronization; verify callers and duplicate-key risk before switching.",
      )
      "alter_identity_generation"
    }
    RemoveIdentity => {
      finding(
        output,
        part,
        number,
        "PG517",
        Warning,
        "DROP IDENTITY removes automatic identity generation and its internal sequence; existing row values remain.",
        "Verify dependencies and future inserts, defaults and key constraints; re-adding identity can generate values conflicting with old data.",
      )
      "drop_identity"
    }
    ReplaceGeneratedExpression => {
      finding(
        output,
        part,
        number,
        "PG518",
        Warning,
        "SET EXPRESSION rewrites stored generated values, but virtual generation affects future reads; actual generation kind is unverified.",
        "Inspect stored/virtual metadata, immutable expression resolution, data/dependencies and ANALYZE requirements; a full rewrite cannot be ruled out from SQL text.",
      )
      "set_generated_expression"
    }
    RemoveGeneratedExpression => {
      finding(
        output,
        part,
        number,
        "PG519",
        Warning,
        "DROP EXPRESSION turns a stored generated column into a base column, preserving stored values but stopping future automatic recomputation.",
        "Verify it is a supported stored generated column, review downstream invariants and IF EXISTS no-op conditions; PostgreSQL does not support this conversion for virtual columns.",
      )
      "drop_generated_expression"
    }
  }
}
