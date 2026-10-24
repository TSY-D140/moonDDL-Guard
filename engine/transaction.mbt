///|
priv enum TransactionStep {
  Start
  Finish(String, Bool)
}

///|
// ROLLBACK TO, PREPARED, and transaction options must not become ordinary ends.
fn transaction_step(tokens : Array[@syntax.Token]) -> TransactionStep? {
  let count = tokens.length()
  if word(tokens, 0, "BEGIN") {
    if count == 1 ||
      (
        count == 2 &&
        (word(tokens, 1, "WORK") || word(tokens, 1, "TRANSACTION"))
      ) {
      return Some(Start)
    }
    return None
  }
  if count == 2 && word(tokens, 0, "START") && word(tokens, 1, "TRANSACTION") {
    return Some(Start)
  }
  let commit = word(tokens, 0, "COMMIT") || word(tokens, 0, "END")
  let rollback = word(tokens, 0, "ROLLBACK") || word(tokens, 0, "ABORT")
  if !commit && !rollback {
    return None
  }
  let kind = if commit { "commit" } else { "rollback" }
  let mut i = 1
  if word(tokens, i, "WORK") || word(tokens, i, "TRANSACTION") {
    i += 1
  }
  if i == count {
    return Some(Finish(kind, false))
  }
  if word(tokens, i, "AND") && word(tokens, i + 1, "CHAIN") && i + 2 == count {
    return Some(Finish(kind, true))
  }
  if word(tokens, i, "AND") &&
    word(tokens, i + 1, "NO") &&
    word(tokens, i + 2, "CHAIN") &&
    i + 3 == count {
    return Some(Finish(kind, false))
  }
  None
}
