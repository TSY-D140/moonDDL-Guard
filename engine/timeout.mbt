///|
priv enum TimeoutValue {
  UnknownTimeout
  Milliseconds(Int64)
  Unrepresentable
}

///|
priv struct TimeoutTracker {
  parameter : String
  mut session : TimeoutValue
  mut saved : TimeoutValue
  mut override_value : TimeoutValue?
  mut scoped : Bool
  mut touched : Bool
}

///|
fn new_timeout(
  parameter : String,
  transaction : Transaction,
  implicit_batch : Bool,
) -> TimeoutTracker {
  {
    parameter,
    session: UnknownTimeout,
    saved: UnknownTimeout,
    override_value: None,
    scoped: transaction == Active || implicit_batch,
    touched: false,
  }
}

///|
fn TimeoutTracker::before(self : TimeoutTracker, implicit_batch : Bool) -> Unit {
  if implicit_batch && !self.scoped {
    self.saved = self.session
    self.override_value = None
    self.scoped = true
  }
}

///|
fn TimeoutTracker::begin(
  self : TimeoutTracker,
  transaction : Transaction,
  delivery : Delivery,
) -> Unit {
  if !self.scoped {
    self.saved = if transaction == UnknownTransaction ||
      delivery == UnknownDelivery {
      UnknownTimeout
    } else {
      self.session
    }
    self.scoped = true
  }
}

///|
fn TimeoutTracker::finish(
  self : TimeoutTracker,
  rollback : Bool,
  chain : Bool,
  transaction : Transaction,
  delivery : Delivery,
) -> Unit {
  if rollback {
    if self.scoped {
      self.session = self.saved
    } else if transaction != Autocommit || delivery != PerStatement {
      self.session = UnknownTimeout
    }
  }
  self.override_value = None
  self.scoped = chain
  if chain {
    self.saved = self.session
  }
}

///|
fn TimeoutTracker::invalidate(self : TimeoutTracker) -> Unit {
  self.session = UnknownTimeout
  self.saved = UnknownTimeout
  self.override_value = None
  self.scoped = false
}

///|
fn TimeoutTracker::assign(
  self : TimeoutTracker,
  setting : TimeoutSetting,
  transaction : Transaction,
  delivery : Delivery,
  implicit_batch : Bool,
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> Bool {
  self.touched = true
  if setting.value is Unrepresentable {
    finding(
      output,
      part,
      number,
      "PG304",
      Error,
      "Timeout is outside the supported exact-millisecond range or syntax.",
      "Use DEFAULT or an unambiguous decimal value up to 2147483647ms; avoid octal and rounding, or express the intended budget as integer milliseconds.",
    )
    return false
  }
  if setting.scoped {
    if transaction == Active || implicit_batch {
      self.override_value = Some(setting.value)
    } else if transaction == Autocommit && delivery != UnknownDelivery {
      finding(
        output,
        part,
        number,
        "PG302",
        Warning,
        "SET LOCAL outside a transaction block has no lasting effect.",
        "Use a deliberately scoped transaction or SET SESSION; concurrent index builds require a non-transactional submission.",
      )
    } else {
      self.override_value = Some(UnknownTimeout)
    }
  } else {
    self.session = setting.value
    self.override_value = None // A later SET overrides the current LOCAL value too.
  }
  true
}

///|
fn TimeoutTracker::effective(self : TimeoutTracker) -> TimeoutValue {
  match self.override_value {
    Some(value) => value
    None => self.session
  }
}

///|
fn TimeoutTracker::at_index(
  self : TimeoutTracker,
  output : Array[Finding],
  part : Segment,
  number : Int32,
  subject~ : String = "index",
) -> Unit {
  if !self.touched {
    return
  }
  match self.effective() {
    Milliseconds(0) =>
      finding(
        output,
        part,
        number,
        if self.parameter == "lock_timeout" {
          "PG301"
        } else {
          "PG308"
        },
        if self.parameter == "lock_timeout" {
          Warning
        } else {
          Advisory
        },
        "\{self.parameter} is explicitly disabled for this \{subject}.",
        "Choose an intentional budget; other timeouts may still apply, and this is not a runtime duration estimate.",
      )
    Milliseconds(ms) =>
      finding(
        output,
        part,
        number,
        if self.parameter == "lock_timeout" {
          "PG305"
        } else {
          "PG307"
        },
        Advisory,
        "Effective \{self.parameter} is \{ms}ms for this \{subject}.",
        if self.parameter == "lock_timeout" {
          "This bounds each lock acquisition wait, not the index build's total duration."
        } else {
          "This bounds the statement, including build work; a timeout may abort a concurrent index build."
        },
      )
    _ =>
      finding(
        output,
        part,
        number,
        "PG303",
        Advisory,
        "Effective \{self.parameter} is unknown after DEFAULT, scope expiry or unassessed SQL.",
        "Inspect the runner/session configuration; no inherited default is assumed.",
      )
  }
}

///|
fn timeout_relationship(
  lock : TimeoutTracker,
  statement : TimeoutTracker,
  output : Array[Finding],
  part : Segment,
  number : Int32,
) -> Unit {
  match (lock.effective(), statement.effective()) {
    (Milliseconds(lock_ms), Milliseconds(statement_ms)) if lock_ms > 0 &&
      statement_ms > 0 &&
      lock_ms >= statement_ms =>
      finding(
        output,
        part,
        number,
        "PG306",
        Warning,
        "lock_timeout is not shorter than statement_timeout.",
        "Use a shorter lock wait budget if that is the intent; statement_timeout can trigger before the lock timeout.",
      )
    _ => ()
  }
}
