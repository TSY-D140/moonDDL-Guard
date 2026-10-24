///|
pub(all) suberror ComparisonError {
  IncompatibleBaseline(String)
} derive(@debug.Debug)

///|
pub extend ComparisonError with @debug.Debug::{to_repr}

///|
pub struct ReviewDelta {
  baseline : Review
  current : Review
  introduced : Array[Finding]
  resolved : Array[Finding]
  unchanged : Int32
}

///|
fn finding_identity(review : Review, f : Finding) -> String {
  let sql = if f.statement > 0 && f.statement <= review.statements.length() {
    review.statements[f.statement - 1].sql
  } else {
    review.source
  }
  (
    {
      "sql": sql,
      "code": f.code,
      "severity": f.severity.to_json(),
      "message": f.message,
      "action": f.action,
    } : Json).stringify()
}

///|
/// Compare exact statement SQL and diagnostic semantics as occurrence-counted
/// identities. Source positions may move; execution contexts must match.
/// Baselines must be complete. Current incompleteness always returns exit 2.
///
/// ```mbt check
/// test {
///   let r = @moonddl_guard.review_sql(
///     "DROP INDEX old_idx;",
///     transaction=@moonddl_guard.Autocommit,
///     delivery=@moonddl_guard.PerStatement,
///   )
///   let delta = @moonddl_guard.compare_reviews(r, r)
///   assert_eq(r.exit_code(), 1)
///   assert_eq(delta.exit_code(), 0)
/// }
/// ```
pub fn compare_reviews(
  baseline : Review,
  current : Review,
) -> ReviewDelta raise ComparisonError {
  if !baseline.is_complete() {
    raise IncompatibleBaseline(
      "Baseline must be complete; regenerate it from fully assessed SQL before using it as a gate.",
    )
  }
  if baseline.transaction != current.transaction ||
    baseline.delivery != current.delivery {
    raise IncompatibleBaseline(
      "Execution contexts differ; regenerate the baseline with the same actual transaction and delivery context.",
    )
  }
  let queues : Map[String, Array[Int32]] = Map([])
  let cursors : Map[String, Int32] = Map([])
  for i, f in baseline.findings {
    let key = finding_identity(baseline, f)
    match queues.get(key) {
      Some(indices) => indices.push(i)
      None => queues[key] = [i]
    }
  }
  let matched = baseline.findings.map(_ => false)
  let introduced : Array[Finding] = []
  let resolved : Array[Finding] = []
  let mut unchanged = 0
  for f in current.findings {
    let key = finding_identity(current, f)
    let cursor = cursors.get(key).unwrap_or(0)
    if queues.get(key) is Some(indices) && cursor < indices.length() {
      matched[indices[cursor]] = true
      cursors[key] = cursor + 1
      unchanged += 1
    } else {
      introduced.push(f)
    }
  }
  for i, f in baseline.findings {
    if !matched[i] {
      resolved.push(f)
    }
  }
  { baseline, current, introduced, resolved, unchanged, }
}

///|
pub fn ReviewDelta::introduced(self : ReviewDelta) -> Array[Finding] {
  self.introduced.copy()
}

///|
pub fn ReviewDelta::resolved(self : ReviewDelta) -> Array[Finding] {
  self.resolved.copy()
}

///|
pub fn ReviewDelta::unchanged_count(self : ReviewDelta) -> Int32 {
  self.unchanged
}

///|
/// 2 = current analysis incomplete; 1 = introduced warning/error; 0 = neither.
/// Existing warnings and introduced advisories remain visible in the report.
pub fn ReviewDelta::exit_code(self : ReviewDelta) -> Int32 {
  if !self.current.is_complete() {
    2
  } else if self.introduced.any(f => f.severity != Advisory) {
    1
  } else {
    0
  }
}

///|
pub fn ReviewDelta::to_json(self : ReviewDelta) -> Json {
  {
    "format": "moonddl.delta.v1",
    "baseline": self.baseline.to_json(),
    "current": self.current.to_json(),
    "introduced": Json(self.introduced),
    "resolved": Json(self.resolved),
    "unchanged": self.unchanged,
    "exit_code": self.exit_code(),
  }
}

///|
pub fn ReviewDelta::to_text(self : ReviewDelta) -> String {
  let out = StringBuilder()
  out.write_string(
    "Review delta: \{self.introduced.length()} introduced; \{self.resolved.length()} resolved; \{self.unchanged} unchanged findings; delta exit=\{self.exit_code()}.\n",
  )
  for f in self.introduced {
    out.write_string(
      "Introduced \{f.code} at current \{f.location.line}:\{f.location.column}: \{f.message}\n  Next: \{f.action}\n",
    )
  }
  for f in self.resolved {
    out.write_string(
      "Resolved \{f.code} at baseline \{f.location.line}:\{f.location.column}: \{f.message}\n",
    )
  }
  out.write_string(
    "Full current review (its exit code is independent of the delta gate):\n",
  )
  out.write_string(self.current.to_text())
  out.to_string()
}

///|
/// Replay both retained reviews and recompute the entire comparison.
/// Unknown/duplicate fields and edited derived results are rejected.
pub fn decode_delta(text : String) -> ReviewDelta raise ReportError {
  if text.length() > 16777216 {
    raise InvalidReport("Delta exceeds the 16 Mi UTF-16 code-unit limit.")
  }
  let value = @json.parse(text) catch {
    _ => raise InvalidReport("Malformed delta JSON.")
  }
  reject_duplicate_keys(text)
  guard value
    is {
      "format": String("moonddl.delta.v1"),
      "baseline": before,
      "current": after,
      ..
    } else {
    raise InvalidReport(
      "Expected moonddl.delta.v1 with baseline and current reports.",
    )
  }
  let baseline = decode_report(before.stringify())
  let current = decode_report(after.stringify())
  let delta = compare_reviews(baseline, current) catch {
    error => raise InvalidReport("Incompatible comparison: \{Repr(error)}")
  }
  if delta.to_json() != value {
    raise InvalidReport(
      "Unknown/missing delta fields or inconsistent derived comparison; regenerate it.",
    )
  }
  delta
}
