///|
pub(all) suberror BatchError {
  InvalidBatch(String)
} derive(@debug.Debug)

///|
pub extend BatchError with @debug.Debug::{to_repr}

///|
pub(all) struct MigrationInput {
  path : String
  sql : String
} derive(Eq, @debug.Debug)

///|
pub struct FileReview {
  path : String
  review : Review
} derive(Eq, @debug.Debug)

///|
pub extend MigrationInput with Eq::{equal, not_equal}

///|
pub extend MigrationInput with @debug.Debug::{to_repr}

///|
pub extend FileReview with Eq::{equal, not_equal}

///|
pub extend FileReview with @debug.Debug::{to_repr}

///|
pub struct BatchReview {
  priv transaction : Transaction
  priv delivery : Delivery
  priv files : Array[FileReview]
}

///|
fn validate_file_paths(paths : Array[String]) -> Unit raise BatchError {
  if paths.is_empty() || paths.length() > 256 {
    raise InvalidBatch("Supply 1–256 explicitly ordered SQL paths.")
  }
  let seen : Map[String, Bool] = Map([])
  for path in paths {
    if path.contains("\\") || !path.to_lower().has_suffix(".sql") {
      raise InvalidBatch("Use relative SQL paths with '/' separators: " + path)
    }
    ignore(
      artifact_uri(path) catch {
        _ => raise InvalidBatch("Invalid relative SQL path: " + path)
      },
    )
    let key = path.to_lower()
    if seen.contains(key) {
      raise InvalidBatch("Duplicate or case-colliding SQL path: " + path)
    }
    seen[key] = true
  }
}

///|
/// Review ordered files with an explicit caller guarantee that each file's
/// transaction and lock effects end before the next file. Session settings
/// inherited across boundaries remain unknown rather than being carried or
/// assumed reset. Cross-file transactions are not supported by this API.
///
/// ```mbt check
/// test {
///   let r = @moonddl_guard.review_isolated_files(
///     [{ path: "001-add.sql", sql: "ALTER TABLE orders ADD status text;", }],
///     transaction=@moonddl_guard.Autocommit,
///     delivery=@moonddl_guard.PerStatement,
///   )
///   assert_eq(r.files()[0].path, "001-add.sql")
///   assert_eq(r.exit_code(), 1)
/// }
/// ```
pub fn review_isolated_files(
  inputs : Array[MigrationInput],
  transaction~ : Transaction,
  delivery~ : Delivery,
) -> BatchReview raise BatchError {
  validate_file_paths(inputs.map(f => f.path))
  let mut total = 0
  for input in inputs {
    if input.sql.length() > 1048576 - total {
      raise InvalidBatch(
        "Batch SQL exceeds 1 Mi UTF-16 code units; split the review along actual committed file boundaries.",
      )
    }
    total += input.sql.length()
  }
  let files = inputs.map(input => FileReview::{
    path: input.path,
    review: review_sql(input.sql, transaction~, delivery~),
  })
  let result = BatchReview::{ transaction, delivery, files, }
  if result.to_json().stringify().length() > 8388608 {
    raise InvalidBatch(
      "Batch report exceeds the 8 Mi replay limit; review fewer complete files.",
    )
  }
  result
}

///|
pub fn BatchReview::files(self : BatchReview) -> Array[FileReview] {
  self.files.map(file => FileReview::{
    path: file.path,
    review: {
      source: file.review.source,
      transaction: file.review.transaction,
      delivery: file.review.delivery,
      statements: file.review.statements.copy(),
      findings: file.review.findings.copy(),
    },
  })
}

///|
pub fn BatchReview::is_complete(self : BatchReview) -> Bool {
  self.files.all(f => f.review.is_complete())
}

///|
pub fn BatchReview::exit_code(self : BatchReview) -> Int32 {
  self.files.fold(init=0, fn(code, file) { code.max(file.review.exit_code()) })
}

///|
pub fn BatchReview::to_json(self : BatchReview) -> Json {
  {
    "format": "moonddl.batch.v1",
    "boundaries": "per-file-commit",
    "transaction": self.transaction.to_json(),
    "delivery": self.delivery.to_json(),
    "files": self.files.map(f => {
      Json({ "path": Json(f.path), "review": f.review.to_json() })
    }),
    "complete": self.is_complete(),
    "exit_code": self.exit_code(),
  }
}

///|
pub fn BatchReview::to_text(self : BatchReview) -> String {
  let out = StringBuilder()
  out.write_string(
    "Directory review: \{self.files.length()} ordered files; per-file commit/isolation; exit=\{self.exit_code()}.\n",
  )
  for file in self.files {
    out.write_string("File: " + file.path + "\n")
    out.write_string(file.review.to_text())
    out.write_string("\n")
  }
  out.to_string()
}

///|
priv enum FileDelta {
  ExistingFile(String, ReviewDelta)
  AddedFile(String, Review)
}

///|
pub struct BatchDelta {
  priv baseline : BatchReview
  priv current : BatchReview
  priv entries : Array[FileDelta]
  priv code : Int32
}

///|
/// Existing path order must remain a prefix; newly appended files are gated.
/// Removing/renaming/reordering files requires explicit baseline regeneration.
pub fn compare_batches(
  baseline : BatchReview,
  current : BatchReview,
) -> BatchDelta raise ComparisonError {
  if !baseline.is_complete() ||
    baseline.transaction != current.transaction ||
    baseline.delivery != current.delivery {
    raise IncompatibleBaseline(
      "Batch baseline must be complete and have the same execution context.",
    )
  }
  if baseline.files.length() > current.files.length() {
    raise IncompatibleBaseline(
      "SQL files were removed; review inventory changes and regenerate the baseline explicitly.",
    )
  }
  let entries : Array[FileDelta] = []
  let mut code = 0
  for i, file in current.files {
    if i < baseline.files.length() {
      if baseline.files[i].path != file.path {
        raise IncompatibleBaseline(
          "SQL paths were renamed/reordered or inserted before the baseline prefix: " +
          file.path,
        )
      }
      let delta = compare_reviews(baseline.files[i].review, file.review)
      code = code.max(delta.exit_code())
      entries.push(ExistingFile(file.path, delta))
    } else {
      code = code.max(file.review.exit_code())
      entries.push(AddedFile(file.path, file.review))
    }
  }
  let result = BatchDelta::{ baseline, current, entries, code, }
  if result.to_json().stringify().length() > 8388608 {
    raise IncompatibleBaseline(
      "Batch comparison exceeds the 8 Mi replay limit; use a smaller committed-file review scope.",
    )
  }
  result
}

///|
pub fn BatchDelta::exit_code(self : BatchDelta) -> Int32 {
  self.code
}

///|
pub fn BatchDelta::to_json(self : BatchDelta) -> Json {
  {
    "format": "moonddl.batch-delta.v1",
    "baseline": self.baseline.to_json(),
    "current": self.current.to_json(),
    "files": self.entries.map(entry => {
      match entry {
        ExistingFile(path, delta) =>
          Json({
            "path": Json(path),
            "kind": Json("existing"),
            "delta": delta.to_json(),
          })
        AddedFile(path, review) =>
          Json({
            "path": Json(path),
            "kind": Json("added"),
            "review": review.to_json(),
          })
      }
    }),
    "exit_code": self.code,
  }
}

///|
pub fn BatchDelta::to_text(self : BatchDelta) -> String {
  "Directory baseline gate: exit=\{self.code}. Full path-associated comparison:\n" +
  self.to_json().stringify(indent=2)
}
