///|
priv enum EnumEvolution {
  CreateEnum
  AddEnumValue(Bool, Bool) // IF NOT EXISTS, explicit ordering
  RenameEnumValue
  RenameType
  MoveTypeSchema
}

///|
fn enum_label(tokens : Array[@syntax.Token], i : Int32) -> Bool {
  i < tokens.length() &&
  tokens[i].token_type == @syntax.STRING &&
  @utf8.encode(tokens[i].text).length() <= 63 &&
  !tokens[i].text.contains("\u0000")
}

///|
fn enum_evolution(tokens : Array[@syntax.Token]) -> EnumEvolution? {
  if tokens.length() > 512 || !word(tokens, 1, "TYPE") {
    return None
  }
  let mut i = match tracked_relation_end(tokens, 2) {
    Some(end) => end
    None => return None
  }
  if word(tokens, 0, "CREATE") {
    if !word(tokens, i, "AS") ||
      !word(tokens, i + 1, "ENUM") ||
      i + 2 >= tokens.length() ||
      tokens[i + 2].token_type != @syntax.L_PAREN {
      return None
    }
    i += 3
    let labels : Map[String, Bool] = Map([])
    if i < tokens.length() &&
      tokens[i].token_type == @syntax.R_PAREN &&
      i + 1 == tokens.length() {
      return Some(CreateEnum)
    }
    for ;; {
      if !enum_label(tokens, i) ||
        labels.contains(tokens[i].text) ||
        labels.length() >= 128 {
        return None
      }
      labels[tokens[i].text] = true
      i += 1
      if i < tokens.length() && tokens[i].token_type == @syntax.COMMA {
        i += 1
        continue
      }
      if i + 1 != tokens.length() || tokens[i].token_type != @syntax.R_PAREN {
        return None
      }
      return Some(CreateEnum)
    }
  }
  if !word(tokens, 0, "ALTER") {
    return None
  }
  if word(tokens, i, "RENAME") &&
    word(tokens, i + 1, "TO") &&
    short_identifier(tokens, i + 2) &&
    i + 3 == tokens.length() {
    return Some(RenameType)
  }
  if word(tokens, i, "SET") &&
    word(tokens, i + 1, "SCHEMA") &&
    short_identifier(tokens, i + 2) &&
    i + 3 == tokens.length() {
    return Some(MoveTypeSchema)
  }
  if word(tokens, i, "RENAME") &&
    word(tokens, i + 1, "VALUE") &&
    enum_label(tokens, i + 2) &&
    word(tokens, i + 3, "TO") &&
    enum_label(tokens, i + 4) &&
    i + 5 == tokens.length() {
    return Some(RenameEnumValue)
  }
  if !word(tokens, i, "ADD") || !word(tokens, i + 1, "VALUE") {
    return None
  }
  i += 2
  let exists = word(tokens, i, "IF") &&
    word(tokens, i + 1, "NOT") &&
    word(tokens, i + 2, "EXISTS")
  if exists {
    i += 3
  }
  if !enum_label(tokens, i) {
    return None
  }
  i += 1
  let ordered = word(tokens, i, "BEFORE") || word(tokens, i, "AFTER")
  if ordered {
    if !enum_label(tokens, i + 1) {
      return None
    }
    i += 2
  }
  if i != tokens.length() {
    return None
  }
  Some(AddEnumValue(exists, ordered))
}

///|
fn review_enum_evolution(
  spec : EnumEvolution,
  state : Transaction,
  implicit_batch : Bool,
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> String {
  finding(
    output,
    part,
    number,
    "PG921",
    Advisory,
    "Type names, privileges, dependencies and enum labels/order require catalog and application verification; this review does not simulate type resolution.",
    "Test the actual PostgreSQL 18 schema and all deployed readers/writers. Enum labels are case/space sensitive and bounded to 63 UTF-8 bytes by this profile.",
  )
  match spec {
    CreateEnum => {
      finding(
        output,
        part,
        number,
        "PG922",
        Warning,
        "Enum labels and their initial ordering form a persistent application/data contract; removing values or changing their ordering later is not a simple ALTER TYPE operation.",
        "Choose lifecycle and rollout requirements before introducing an enum; a replacement-type migration can require dependent-column conversions and table rewrites.",
      )
      "create_enum"
    }
    AddEnumValue(exists, ordered) => {
      finding(
        output,
        part,
        number,
        "PG923",
        if state != Autocommit || implicit_batch {
          Warning
        } else {
          Advisory
        },
        "An enum value added in a transaction generally cannot be used until that transaction commits; ADD VALUE itself is permitted in PostgreSQL 18 transactions.",
        "Commit enum extension before migrations/defaults/seeds use the new value. Newly-created types have server-specific visibility exceptions; no exception is inferred here, and unknown initial transaction scope is treated conservatively.",
      )
      finding(
        output,
        part,
        number,
        "PG924",
        Warning,
        if exists {
          "IF NOT EXISTS can skip an existing enum label without verifying its requested placement or application compatibility."
        } else {
          "Adding an enum label can break application enum decoders, exhaustive matches and ordering assumptions."
        },
        "Deploy tolerant readers first, verify the existing type/order, then enable writers of the new value. Plan recovery without assuming DROP VALUE exists.",
      )
      if ordered {
        finding(
          output,
          part,
          number,
          "PG926",
          Warning,
          "BEFORE/AFTER changes the label comparison position; catalog state determines anchor existence and some comparisons can become slower.",
          "Verify the intended sort semantics and representative queries; no performance improvement/regression magnitude is predicted.",
        )
      }
      "add_enum_value"
    }
    RenameEnumValue => {
      finding(
        output,
        part,
        number,
        "PG925",
        Warning,
        "Renaming an enum label changes textual input/output for existing rows while preserving its ordering position; old application literals may stop working.",
        "Coordinate defaults, readers/writers and rollback compatibility; verify old/new labels and dependencies in the target catalog.",
      )
      "rename_enum_value"
    }
    RenameType | MoveTypeSchema => {
      finding(
        output,
        part,
        number,
        "PG927",
        Warning,
        "Renaming or moving a type can break SQL casts, defaults and application name/search_path resolution; object dependencies and collisions are unverified.",
        "Plan a coordinated naming cutover and verify ownership, destination schema privileges and dependent objects. No table lock identity is inferred from a type name.",
      )
      match spec {
        RenameType => "rename_type"
        _ => "move_type_schema"
      }
    }
  }
}
