///|
fn diagnostic_region(part : Segment, start : Int32, end : Int32) -> Segment {
  let offsets = source_offsets(part.sql)
  let origin = part.tokens[0].start
  let begin = offsets[part.tokens[start].start - origin]
  let finish = offsets[part.tokens[end - 1].end + 1 - origin]
  let loc = location_at(part.sql, begin, finish)
  let subset : Array[@syntax.Token] = []
  for i in start..<end {
    subset.push(part.tokens[i])
  }
  {
    tokens: subset,
    sql: part.sql[begin:finish].to_owned(),
    location: {
      start: part.location.start + begin,
      end: part.location.start + finish,
      line: part.location.line + loc.line - 1,
      column: if loc.line == 1 {
        part.location.column + loc.column - 1
      } else {
        loc.column
      },
    },
  }
}

///|
// Called only after every complete supported profile failed. A recognized
// marker explains an unassessed construct, never certifies the other clauses.
fn unsupported_finding(
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> Unit {
  let t = part.tokens
  let mut selected = part
  let mut message = "Statement or clause is outside the supported PostgreSQL migration review profile."
  let mut action = "Retain this SQL for manual review; unsupported input cannot receive a complete verdict."
  if word(t, 0, "DO") {
    selected = diagnostic_region(part, 0, 1)
    message = "Unassessed procedural block: DO can contain conditional/dynamic SQL and transaction-sensitive work; its body was not analyzed."
    action = "Review the entire body and called routines with a PostgreSQL reviewer. Do not remove the block or approve the surrounding file to bypass incomplete coverage."
  } else if word(t, 0, "GRANT") || word(t, 0, "REVOKE") {
    selected = diagnostic_region(part, 0, 1)
    message = "Unassessed privilege change: GRANT/REVOKE effects depend on object identity, roles and effective privileges."
    action = "Inspect the exact objects, grantees, role memberships and dependent application access; keep this input incomplete pending manual privilege review."
  } else if word(t, 0, "CREATE") &&
    (
      word(t, 1, "FUNCTION") ||
      (word(t, 1, "OR") && word(t, 2, "REPLACE") && word(t, 3, "FUNCTION"))
    ) {
    let marker = if word(t, 1, "FUNCTION") { 1 } else { 3 }
    selected = diagnostic_region(part, marker, marker + 1)
    message = "Unassessed routine definition/replacement: body behavior, overload identity, execution privileges and search_path are outside the complete profile."
    action = "Inspect signature, SECURITY DEFINER/INVOKER, search_path, grants and all body/called-routine effects. A routine declaration alone cannot establish body safety."
  } else if word(t, 0, "ALTER") && word(t, 1, "TABLE") && t.length() > 256 {
    selected = diagnostic_region(part, 256, 257)
    message = "ALTER TABLE exceeds the 256-token bounded constraint/column profile."
    action = "Review the entire original statement manually; splitting SQL can change lock, rewrite and atomicity semantics. This tool never truncates the input to fit the limit."
  } else {
    let mut parens = 0
    let mut brackets = 0
    let commas : Array[Int32] = []
    let mut marker : (Int32, String, String)? = None
    for i, token in t {
      if token.token_type == @syntax.L_PAREN {
        parens += 1
      }
      if token.token_type == @syntax.R_PAREN {
        parens -= 1
      }
      if token.token_type == @syntax.L_BRACKET {
        brackets += 1
      }
      if token.token_type == @syntax.R_BRACKET {
        brackets -= 1
      }
      if token.token_type == @syntax.COMMA && parens == 0 && brackets == 0 {
        commas.push(i)
      }
      if marker is None {
        if word(t, i, "COLLATE") {
          marker = Some(
            (
              i, "Unassessed COLLATE clause in this statement; collation/operator eligibility is not established.",
              "Inspect the collation and operator/index/type contracts using handbook/rule-coverage.md. Preserve this clause and keep the statement incomplete.",
            ),
          )
        } else if token.token_type == @syntax.L_BRACKET {
          marker = Some(
            (
              i, "Unassessed array/subscript syntax in this statement; the scalar profile does not establish these semantics.",
              "Review array element types, casts, expressions and affected values as a complete workflow; do not remove brackets or casts to obtain a complete verdict.",
            ),
          )
        } else if word(t, 0, "INSERT") && word(t, i, "SELECT") && parens == 0 {
          marker = Some(
            (
              i, "Unassessed INSERT query source: source-driven insertion is outside the bounded VALUES/default seed profile.",
              "Inspect source cardinality, source/target dependencies, expressions, conflicts, retries and transaction duration; review the original INSERT SELECT as a whole.",
            ),
          )
        }
      }
    }
    if word(t, 0, "ALTER") && word(t, 1, "TABLE") && !commas.is_empty() {
      let at = if commas.length() >= 32 { commas[31] } else { commas[0] }
      selected = diagnostic_region(part, at, at + 1)
      message = if commas.length() >= 32 {
        "Combined ALTER TABLE exceeds the 32-action profile."
      } else {
        "Combined ALTER TABLE did not fully match the ordinary multi-ADD profile: an action, name, clause or bound is unassessed."
      }
      action = "Check every action against handbook/combined-additions.md: only ordinary ADD COLUMN, unique names, 32 actions, 32 nesting levels and 63-byte names are supported. Mixed DROP/ALTER, generation and unknown expressions require whole-statement manual review."
    } else if marker is Some((at, reason, advice)) {
      selected = diagnostic_region(part, at, at + 1)
      message = reason
      action = advice
    }
  }
  finding(output, selected, number, "PG002", Error, message, action)
}
