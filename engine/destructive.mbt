///|
priv enum RemovalKind {
  RemoveTable
  RemoveColumn
  RemoveConstraint
  TruncateTable(Bool)
}

///|
priv struct RemovalSpec {
  kind : RemovalKind
  tables : Array[String]
  cascade : Bool
}

///|
fn removal_suffix(tokens : Array[@syntax.Token], start : Int32) -> Bool? {
  if start == tokens.length() {
    return Some(false)
  }
  if start + 1 != tokens.length() {
    return None
  }
  if word(tokens, start, "CASCADE") {
    Some(true)
  } else if word(tokens, start, "RESTRICT") {
    Some(false)
  } else {
    None
  }
}

///|
fn removal_member(
  tokens : Array[@syntax.Token],
  start : Int32,
  table : String,
) -> RemovalSpec? {
  if !word(tokens, start, "DROP") {
    return None
  }
  let constraint = word(tokens, start + 1, "CONSTRAINT")
  let mut i = start + 1
  if constraint || word(tokens, i, "COLUMN") {
    i += 1
  }
  if word(tokens, i, "IF") && word(tokens, i + 1, "EXISTS") {
    i += 2
  }
  if i >= tokens.length() ||
    !is_identifier(tokens[i]) ||
    tokens[i].text.is_empty() {
    return None
  }
  let cascade = match removal_suffix(tokens, i + 1) {
    Some(cascade) => cascade
    None => return None
  }
  Some({
    kind: if constraint {
      RemoveConstraint
    } else {
      RemoveColumn
    },
    tables: [table],
    cascade,
  })
}

///|
fn removal_tables(tokens : Array[@syntax.Token]) -> RemovalSpec? {
  if tokens.length() > 256 {
    return None
  }
  let truncate = word(tokens, 0, "TRUNCATE")
  let mut i = if truncate {
    if word(tokens, 1, "TABLE") {
      2
    } else {
      1
    }
  } else {
    if !word(tokens, 0, "DROP") || !word(tokens, 1, "TABLE") {
      return None
    }
    if word(tokens, 2, "IF") && word(tokens, 3, "EXISTS") {
      4
    } else {
      2
    }
  }
  let tables : Array[String] = []
  for ;; {
    let only = truncate && word(tokens, i, "ONLY")
    if only {
      i += 1
    }
    let first = i
    i = match tracked_relation_end(tokens, i) {
      Some(end) => end
      None => return None
    }
    tables.push(constraint_table_key(tokens, first, i))
    if tables.length() > 32 {
      return None
    }
    if truncate && i < tokens.length() && tokens[i].token_type == @syntax.STAR {
      if only {
        return None
      }
      i += 1
    }
    if i < tokens.length() && tokens[i].token_type == @syntax.COMMA {
      i += 1
      continue
    }
    break
  }
  let restart = truncate && word(tokens, i, "RESTART")
  if restart || (truncate && word(tokens, i, "CONTINUE")) {
    if !word(tokens, i + 1, "IDENTITY") {
      return None
    }
    i += 2
  }
  let cascade = match removal_suffix(tokens, i) {
    Some(cascade) => cascade
    None => return None
  }
  Some({
    kind: if truncate {
      TruncateTable(restart)
    } else {
      RemoveTable
    },
    tables,
    cascade,
  })
}

///|
fn review_removal(
  spec : RemovalSpec,
  held : Map[String, HeldTableLock],
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  for table in spec.tables {
    held[table] = AccessExclusive
  }
  finding(
    output,
    part,
    number,
    "PG601",
    Warning,
    "This destructive operation takes ACCESS EXCLUSIVE on its affected table(s) until transaction end.",
    "Review the full affected set, lock ordering and lock/statement budgets; verify a recovery plan before execution.",
  )
  let operation = match spec.kind {
    RemoveConstraint => {
      finding(
        output,
        part,
        number,
        "PG605",
        Warning,
        "Dropping a constraint removes its integrity protection and any index owned by that constraint.",
        "Inspect the actual constraint type, dependent foreign keys and supporting index ownership; future invalid writes can make restoring the constraint fail.",
      )
      "drop_constraint"
    }
    RemoveColumn => {
      finding(
        output,
        part,
        number,
        "PG602",
        Warning,
        "Dropping a column removes SQL access to its data and automatically removes local indexes/constraints involving it.",
        "Verify backups and application compatibility before commit; DROP COLUMN does not immediately reclaim its physical disk space.",
      )
      "drop_column"
    }
    RemoveTable => {
      finding(
        output,
        part,
        number,
        "PG602",
        Warning,
        "Dropping a table removes its data, indexes, triggers, rules and constraints.",
        "Verify the exact target, backups and application cutover; IF EXISTS does not make an existing table disposable.",
      )
      "drop_table"
    }
    TruncateTable(restart) => {
      finding(
        output,
        part,
        number,
        "PG602",
        Warning,
        "TRUNCATE removes every row from its affected tables, including descendants unless ONLY restricts the target.",
        "Verify backups and the full descendant/reference set; transaction rollback can undo TRUNCATE, but committed data loss requires a recovery source.",
      )
      finding(
        output,
        part,
        number,
        "PG607",
        Advisory,
        "TRUNCATE fires ON TRUNCATE rather than ON DELETE triggers and is not MVCC-safe for older snapshots.",
        "Review audit/trigger behavior and concurrent readers; this is not an interchangeable row-by-row DELETE workflow.",
      )
      if restart {
        finding(
          output,
          part,
          number,
          "PG606",
          Warning,
          "RESTART IDENTITY also restarts owned sequences and locks them exclusively.",
          "Review identifier reuse and sequence-dependent consumers; verify rollback and currval behavior if the transaction fails.",
        )
      }
      "truncate_table"
    }
  }
  if spec.cascade {
    finding(
      output,
      part,
      number,
      "PG603",
      Warning,
      match spec.kind {
        TruncateTable(_) =>
          "TRUNCATE CASCADE can remove rows from additional referencing tables and their partitions."
        _ =>
          "CASCADE can recursively remove dependent objects beyond the explicitly named target."
      },
      "Inspect the dependency graph before execution; the affected set cannot be established from this SQL text alone.",
    )
  }
  finding(
    output,
    part,
    number,
    "PG604",
    Advisory,
    "Object existence, privileges, dependencies, descendants and recovery resources have not been inspected.",
    "RESTRICT can prevent external dependency removal but does not preserve the target or its local owned objects. Verify catalog preconditions; static findings describe a successful execution path.",
  )
  operation
}
