///|
priv enum SavepointStep {
  CreatePoint(String)
  RewindPoint(String)
  ReleasePoint(String)
}

///|
priv struct SavepointFrame {
  name : String
  lock : TimeoutTracker
  statement : TimeoutTracker
  held : Map[String, Bool]
}

///|
fn savepoint_step(tokens : Array[@syntax.Token]) -> SavepointStep? {
  let mut i = 1
  let kind = if word(tokens, 0, "SAVEPOINT") {
    0
  } else if word(tokens, 0, "RELEASE") {
    1
  } else if word(tokens, 0, "ROLLBACK") {
    if word(tokens, i, "WORK") || word(tokens, i, "TRANSACTION") {
      i += 1
    }
    if !word(tokens, i, "TO") {
      return None
    }
    i += 1
    2
  } else {
    return None
  }
  if kind != 0 && word(tokens, i, "SAVEPOINT") {
    i += 1
  }
  if i + 1 != tokens.length() ||
    !is_identifier(tokens[i]) ||
    tokens[i].text.is_empty() ||
    @utf8.encode(tokens[i].text).length() > 63 {
    return None
  }
  let name = constraint_table_key(tokens, i, i + 1)
  Some(
    match kind {
      0 => CreatePoint(name)
      1 => ReleasePoint(name)
      _ => RewindPoint(name)
    },
  )
}

///|
fn TimeoutTracker::snapshot(self : TimeoutTracker) -> TimeoutTracker {
  {
    parameter: self.parameter,
    session: self.session,
    saved: self.saved,
    override_value: self.override_value,
    scoped: self.scoped,
    touched: self.touched,
  }
}

///|
fn TimeoutTracker::restore(
  self : TimeoutTracker,
  saved : TimeoutTracker,
) -> Unit {
  self.session = saved.session
  self.saved = saved.saved
  self.override_value = saved.override_value
  self.scoped = saved.scoped
  self.touched = self.touched || saved.touched
}

///|
fn apply_savepoint(
  step : SavepointStep,
  stack : Array[SavepointFrame],
  transaction : Transaction,
  lock : TimeoutTracker,
  statement : TimeoutTracker,
  held : Map[String, Bool],
) -> String? {
  // Implicit Simple Query blocks do not allow savepoints.
  if transaction != Active {
    return None
  }
  match step {
    CreatePoint(name) => {
      if stack.length() >= 64 {
        return None
      }
      stack.push({
        name,
        lock: lock.snapshot(),
        statement: statement.snapshot(),
        held: held.copy(),
      })
      Some("savepoint")
    }
    RewindPoint(name) | ReleasePoint(name) => {
      let mut found = -1
      for i in 0..<stack.length() {
        if stack[i].name == name {
          found = i
        }
      }
      if found < 0 {
        return None
      }
      let rewind = step is RewindPoint(_)
      if rewind {
        let saved = stack[found]
        lock.restore(saved.lock)
        statement.restore(saved.statement)
        held.clear()
        for key, value in saved.held {
          held[key] = value
        }
      }
      let retain = if rewind { found + 1 } else { found }
      while stack.length() > retain {
        ignore(stack.pop())
      }
      Some(if rewind { "rollback_to_savepoint" } else { "release_savepoint" })
    }
  }
}
