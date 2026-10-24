///|
priv struct Segment {
  tokens : Array[@syntax.Token]
  location : Location
  sql : String
}

///|
fn source_offsets(source : String) -> Array[Int32] {
  let offsets = [0]
  let mut offset = 0
  for ch in source {
    offset += if ch.to_int() > 0xffff { 2 } else { 1 }
    offsets.push(offset)
  }
  offsets
}

///|
fn location_at(source : String, start : Int32, end : Int32) -> Location {
  let mut line = 1
  let mut column = 1
  let mut previous_cr = false
  for i in 0..<start {
    let code = source.code_unit_at(i)
    if code == 13 {
      line += 1
      column = 1
      previous_cr = true
    } else if code == 10 {
      if !previous_cr {
        line += 1
      }
      column = 1
      previous_cr = false
    } else {
      column += 1
      previous_cr = false
    }
  }
  { start, end, line, column, }
}

///|
fn segments(source : String) -> Array[Segment] raise @syntax.SqlglotError {
  let tokens = @sqlglot.dialect("postgres").tokenize(source)
  let offsets = source_offsets(source)
  let result : Array[Segment] = []
  let mut group : Array[@syntax.Token] = []
  for token in tokens {
    if token.token_type == @syntax.SEMICOLON {
      if !group.is_empty() {
        let start = offsets[group[0].start]
        let end = offsets[token.end + 1]
        result.push({
          tokens: group,
          location: location_at(source, start, end),
          sql: source[start:end].to_owned(),
        })
        group = []
      }
    } else {
      group.push(token)
    }
  }
  if !group.is_empty() {
    let start = offsets[group[0].start]
    let end = offsets[group[group.length() - 1].end + 1]
    result.push({
      tokens: group,
      location: location_at(source, start, end),
      sql: source[start:end].to_owned(),
    })
  }
  result
}

///|
fn is_identifier(token : @syntax.Token) -> Bool {
  token.token_type == @syntax.VAR || token.token_type == @syntax.IDENTIFIER
}

///|
fn word(tokens : Array[@syntax.Token], i : Int32, text : String) -> Bool {
  if i >= tokens.length() {
    return false
  }
  match tokens[i].token_type {
    @syntax.IDENTIFIER
    | @syntax.STRING
    | @syntax.NUMBER
    | @syntax.BIT_STRING
    | @syntax.HEX_STRING
    | @syntax.BYTE_STRING
    | @syntax.NATIONAL_STRING
    | @syntax.RAW_STRING
    | @syntax.HEREDOC_STRING
    | @syntax.UNICODE_STRING => false
    _ => tokens[i].text.to_upper() == text
  }
}

///|
priv struct IndexSpec {
  unique : Bool
  concurrent : Bool
  exists : Bool
}

///|
// A whitelist on top of SQLGlot, not a claim that every parsed AST is supported.
fn index_spec(tokens : Array[@syntax.Token]) -> IndexSpec? {
  if !word(tokens, 0, "CREATE") {
    return None
  }
  let mut i = 1
  let unique = word(tokens, i, "UNIQUE")
  if unique {
    i += 1
  }
  if !word(tokens, i, "INDEX") {
    return None
  }
  i += 1
  let concurrent = word(tokens, i, "CONCURRENTLY")
  if concurrent {
    i += 1
  }
  let exists = word(tokens, i, "IF")
  if exists {
    if !word(tokens, i + 1, "NOT") || !word(tokens, i + 2, "EXISTS") {
      return None
    }
    i += 3
  }
  if i >= tokens.length() || !is_identifier(tokens[i]) {
    return None
  }
  i += 1
  if !word(tokens, i, "ON") {
    return None
  }
  i += 1
  if i >= tokens.length() || !is_identifier(tokens[i]) {
    return None
  }
  i += 1
  if i < tokens.length() && tokens[i].token_type == @syntax.DOT {
    i += 1
    if i >= tokens.length() || !is_identifier(tokens[i]) {
      return None
    }
    i += 1
  }
  if word(tokens, i, "USING") {
    if !word(tokens, i + 1, "BTREE") {
      return None
    }
    i += 2
  }
  i = match parenthesized_end(tokens, i) {
    Some(end) => end
    None => return None
  }
  if word(tokens, i, "INCLUDE") {
    i += 1
    if i >= tokens.length() || tokens[i].token_type != @syntax.L_PAREN {
      return None
    }
    i += 1
    for ;; {
      if i >= tokens.length() || !is_identifier(tokens[i]) {
        return None
      }
      i += 1
      if i < tokens.length() && tokens[i].token_type == @syntax.COMMA {
        i += 1
        continue
      }
      break
    }
    if i >= tokens.length() || tokens[i].token_type != @syntax.R_PAREN {
      return None
    }
    i += 1
  }
  if word(tokens, i, "WHERE") {
    if i + 1 == tokens.length() {
      return None
    }
    // SQLGlot parses the predicate; the AST whitelist below checks its scope.
    i = tokens.length()
  }
  if i != tokens.length() {
    return None
  }
  Some({ unique, concurrent, exists, })
}

///|
fn parenthesized_end(tokens : Array[@syntax.Token], start : Int32) -> Int32? {
  if start >= tokens.length() || tokens[start].token_type != @syntax.L_PAREN {
    return None
  }
  let mut depth = 0
  for i in start..<tokens.length() {
    if tokens[i].token_type == @syntax.L_PAREN {
      depth += 1
    }
    if depth > 32 {
      return None
    }
    if tokens[i].token_type == @syntax.R_PAREN {
      depth -= 1
      if depth == 0 {
        return Some(i + 1)
      }
    }
  }
  None
}
