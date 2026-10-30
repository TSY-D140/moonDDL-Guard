///|
priv struct ObjectRemovalSpec {
  kind : String
  cascade : Bool
  table : String?
}

///|
// Explicit argument types identify an overload; names/modes/arrays remain outside
// this profile rather than being normalized away.
fn removal_signature(tokens : Array[@syntax.Token], start : Int32) -> Int32? {
  if start >= tokens.length() || tokens[start].token_type != @syntax.L_PAREN {
    return None
  }
  let mut i = start + 1
  if i < tokens.length() && tokens[i].token_type == @syntax.R_PAREN {
    return Some(i + 1)
  }
  let mut count = 0
  for ;; {
    i = match column_type(tokens, i) {
      Some((end, _)) => end
      None => return None
    }
    count += 1
    if count > 32 || i >= tokens.length() {
      return None
    }
    if tokens[i].token_type == @syntax.COMMA {
      i += 1
      continue
    }
    if tokens[i].token_type == @syntax.R_PAREN {
      return Some(i + 1)
    }
    return None
  }
}

///|
fn object_removal(tokens : Array[@syntax.Token]) -> ObjectRemovalSpec? {
  if tokens.length() > 512 || !word(tokens, 0, "DROP") {
    return None
  }
  let mut i = 2
  let kind = if word(tokens, 1, "MATERIALIZED VIEW") {
    "materialized_view"
  } else if word(tokens, 1, "MATERIALIZED") && word(tokens, 2, "VIEW") {
    i += 1
    "materialized_view"
  } else {
    let mut found = ""
    for
      name in [
        "VIEW", "SEQUENCE", "TYPE", "DOMAIN", "SCHEMA", "EXTENSION", "FUNCTION",
        "PROCEDURE", "TRIGGER", "POLICY",
      ] {
      if word(tokens, 1, name) {
        found = name.to_lower()
        break
      }
    }
    if found == "" {
      return None
    }
    found
  }
  if word(tokens, i, "IF") && word(tokens, i + 1, "EXISTS") {
    i += 2
  }
  let mut table : String? = None
  if kind == "trigger" || kind == "policy" {
    if !short_identifier(tokens, i) || !word(tokens, i + 1, "ON") {
      return None
    }
    let first = i + 2
    i = match tracked_relation_end(tokens, first) {
      Some(end) => end
      None => return None
    }
    table = Some(constraint_table_key(tokens, first, i))
  } else {
    let mut count = 0
    for ;; {
      if kind == "schema" || kind == "extension" {
        if !short_identifier(tokens, i) &&
          !(kind == "extension" && word(tokens, i, "HSTORE")) {
          return None
        }
        i += 1
      } else {
        let first = i
        i = match tracked_relation_end(tokens, i) {
          Some(end) => end
          None => return None
        }
        if kind == "function" || kind == "procedure" {
          i = match removal_signature(tokens, i) {
            Some(end) => end
            None => return None
          }
          for j in first..<i {
            if is_identifier(tokens[j]) && !short_identifier(tokens, j) {
              return None
            }
          }
        }
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
  }
  let cascade = match removal_suffix(tokens, i) {
    Some(value) => value
    None => return None
  }
  Some({ kind, cascade, table, })
}

///|
fn review_object_removal(
  spec : ObjectRemovalSpec,
  held : Map[String, HeldTableLock],
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  finding(
    output,
    part,
    number,
    "PG631",
    Warning,
    "DROP " +
    spec.kind.to_upper().replace_all(old="_", new=" ") +
    " removes a database/application contract; IF EXISTS only tolerates absence.",
    "Inventory readers, writers, stored definitions and ownership/privileges, capture a recovery definition/data source, and coordinate the cutover. RESTRICT does not preserve the explicitly removed object.",
  )
  if spec.cascade && spec.kind != "policy" {
    finding(
      output,
      part,
      number,
      "PG632",
      Error,
      "CASCADE can recursively remove dependent objects; type/domain removal can remove dependent table columns, and schema/extension removal can destroy objects and data.",
      "Inspect pg_depend and the full affected object/column set before approval. This offline review does not compute dependency closure or a recovery script.",
    )
  }
  finding(
    output,
    part,
    number,
    "PG633",
    Advisory,
    "Object existence, dependency/extension ownership, overload resolution and the full lock set are catalog-dependent and unverified.",
    "Check the target database and lock/statement budgets. DDL rollback before commit is different from restoring committed data loss; no database execution occurs here.",
  )
  if spec.table is Some(table) {
    held[table] = AccessExclusive
    finding(
      output,
      part,
      number,
      "PG634",
      Warning,
      "Dropping this table-owned trigger/policy takes ACCESS EXCLUSIVE on its owning table, retained until transaction end.",
      "Separate the metadata cutover from subsequent data changes, and verify partition/internal-trigger restrictions and lock ordering.",
    )
  }
  if spec.kind == "policy" {
    finding(
      output,
      part,
      number,
      "PG635",
      Warning,
      "Removing an RLS policy changes access decisions; removing the last policy while RLS remains enabled applies default-deny. CASCADE/RESTRICT have no effect for DROP POLICY.",
      "Review permissive/restrictive policy combinations, RLS enabled/forced state and non-bypass application roles; do not assume dropping a policy disables RLS.",
    )
  }
  if spec.kind == "trigger" {
    finding(
      output,
      part,
      number,
      "PG636",
      Warning,
      "Removing a trigger can disable integrity, audit or replication side effects; internal/dependent triggers cannot always be removed independently.",
      "Inspect trigger function, constraint ownership, event coverage and partition clones; test downstream data behavior before committing.",
    )
  }
  if spec.kind == "sequence" {
    finding(
      output,
      part,
      number,
      "PG637",
      Warning,
      "Dropping a sequence removes its counter state; CASCADE can remove dependent defaults, and owned/identity dependencies can prevent independent removal.",
      "Inspect sequence ownership and nextval callers. Recreating a name does not restore its previous value or prevent future duplicate keys.",
    )
  }
  if spec.kind == "materialized_view" ||
    spec.kind == "schema" ||
    spec.kind == "extension" {
    finding(
      output,
      part,
      number,
      "PG638",
      Warning,
      "This removal can discard stored materialized data or contained/member objects and their grants/dependencies.",
      "Inventory definitions and data, including cross-schema members; prepare the actual rebuild/restore and access-control plan before deployment.",
    )
  }
  "drop_" + spec.kind
}
