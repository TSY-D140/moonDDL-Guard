///|
pub(all) suberror ExportError {
  InvalidArtifactPath(String)
} derive(@debug.Debug)

///|
pub extend ExportError with @debug.Debug::{to_repr}

///|
fn artifact_uri(path : String) -> String raise ExportError {
  let normalized = path.replace_all(old="\\", new="/")
  if normalized.is_empty() ||
    normalized.length() > 4096 ||
    normalized.contains(":") ||
    normalized.split("/").any(s => s == "" || s == "." || s == "..") {
    raise InvalidArtifactPath(
      "Supply a nonempty repository-relative file path without drive, scheme or dot segments.",
    )
  }
  let mut i = 0
  while i < normalized.length() {
    let code = normalized.code_unit_at(i)
    if code >= 0xd800 && code <= 0xdbff {
      if i + 1 >= normalized.length() ||
        normalized.code_unit_at(i + 1) < 0xdc00 ||
        normalized.code_unit_at(i + 1) > 0xdfff {
        raise InvalidArtifactPath(
          "Artifact path contains an unpaired UTF-16 surrogate.",
        )
      }
      i += 2
    } else {
      if code >= 0xdc00 && code <= 0xdfff {
        raise InvalidArtifactPath(
          "Artifact path contains an unpaired UTF-16 surrogate.",
        )
      }
      i += 1
    }
  }
  for ch in normalized {
    if ch.to_int() < 32 || ch.to_int() == 127 {
      raise InvalidArtifactPath(
        "Artifact paths must not contain control characters.",
      )
    }
  }
  let encoded = StringBuilder()
  let hex = "0123456789ABCDEF"
  for byte in @utf8.encode(normalized) {
    let n = byte.to_int()
    if (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 45 ||
      n == 46 ||
      n == 95 ||
      n == 126 ||
      n == 47 {
      encoded.write_char(n.to_char().unwrap())
    } else {
      encoded.write_string("%")
      encoded.write_string(hex[n / 16:n / 16 + 1].to_owned())
      encoded.write_string(hex[n % 16:n % 16 + 1].to_owned())
    }
  }
  encoded.to_string()
}

///|
fn sarif_rules() -> Array[Json] {
  [
    ("PG000", "Lexical or resource limit"),
    ("PG001", "Index syntax"),
    ("PG002", "Unassessed SQL"),
    ("PG101", "Write-blocking index build"),
    ("PG103", "Unique data precondition"),
    ("PG104", "Existing index precondition"),
    ("PG105", "Concurrent build recovery"),
    ("PG106", "Expression immutability"),
    ("PG107", "Partial index semantics"),
    ("PG108", "Covering payload"),
    ("PG109", "Access-blocking index drop"),
    ("PG110", "Drop catalog preconditions"),
    ("PG111", "Invalid concurrent drop options"),
    ("PG112", "Cascading removal"),
    ("PG201", "Concurrent build in transaction"),
    ("PG202", "Unknown build context"),
    ("PG203", "Nested BEGIN"),
    ("PG204", "Unclosed transaction"),
    ("PG205", "Unmatched transaction end"),
    ("PG206", "Concurrent drop in transaction"),
    ("PG207", "Unknown drop context"),
    ("PG208", "Unknown or unsupported savepoint scope"),
    ("PG301", "Disabled lock timeout"),
    ("PG302", "Ineffective LOCAL"),
    ("PG303", "Unknown timeout"),
    ("PG304", "Unassessed timeout value"),
    ("PG305", "Effective lock budget"),
    ("PG306", "Conflicting timeout budgets"),
    ("PG307", "Effective statement budget"),
    ("PG308", "Disabled statement timeout"),
    ("PG401", "Strong CHECK addition lock"),
    ("PG402", "Immediate CHECK scan"),
    ("PG403", "Unvalidated old rows"),
    ("PG404", "Validation preconditions"),
    ("PG405", "Retained strong lock"),
    ("PG406", "CHECK expression semantics"),
  ].map(pair => {
    let (code, label) = pair
    {
      "id": code,
      "shortDescription": { "text": label },
      "helpUri": "https://github.com/TSY-D140/moonDDL-Guard",
    }
  })
}

///|
/// Export SARIF 2.1.0 with a repository-relative filesystem path (not a URI).
/// Backslashes become separators; reserved/non-ASCII bytes are percent encoded.
/// The retained review remains available in run.properties.moonddlReview.
///
/// ```mbt check
/// test {
///   let r = @moonddl_guard.review_sql(
///     "",
///     transaction=@moonddl_guard.Autocommit,
///     delivery=@moonddl_guard.PerStatement,
///   )
///   assert_true(r.to_sarif("migrations/change.sql").stringify().contains("2.1.0"))
/// }
/// ```
pub fn Review::to_sarif(
  self : Review,
  artifact_path : String,
) -> Json raise ExportError {
  let uri = artifact_uri(artifact_path)
  let results = self.findings.map(f => {
    let level = match f.severity {
      Error => "error"
      Warning => "warning"
      Advisory => "note"
    }
    (
      {
        "ruleId": f.code,
        "level": level,
        "message": { "text": f.message + "\nNext: " + f.action },
        "locations": [
          {
            "physicalLocation": {
              "artifactLocation": { "uri": uri, "index": 0 },
              "region": {
                "startLine": f.location.line,
                "startColumn": f.location.column,
                "charOffset": f.location.start,
                "charLength": f.location.end - f.location.start,
              },
            },
          },
        ],
        "properties": {
          "statement": f.statement,
          "severity": f.severity.to_json(),
        },
      } : Json)
  })
  {
    "$schema": "https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/schemas/sarif-schema-2.1.0.json",
    "version": "2.1.0",
    "runs": [
      {
        "tool": {
          "driver": {
            "name": "MoonDDL Guard",
            "semanticVersion": "0.10.0",
            "informationUri": "https://github.com/TSY-D140/moonDDL-Guard",
            "rules": Json(sarif_rules()),
          },
        },
        "columnKind": "utf16CodeUnits",
        "artifacts": [
          {
            "location": { "uri": uri },
            "contents": { "text": self.source },
            "sourceLanguage": "sql",
          },
        ],
        "invocations": [{ "executionSuccessful": self.is_complete() }],
        "results": Json(results),
        "properties": { "moonddlReview": self.to_json() },
      },
    ],
  }
}
