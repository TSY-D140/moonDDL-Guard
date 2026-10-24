///|
pub(all) suberror ReportError {
  InvalidReport(String)
} derive(@debug.Debug)

///|
pub extend ReportError with @debug.Debug::{to_repr}

///|
priv enum JsonContainer {
  ObjectKeys(Map[String, Bool])
  ListValue
}

///|
// JSON is parsed first. This pass only rejects duplicate object members,
// including escaped spellings of the same key, before any data can be lost.
fn reject_duplicate_keys(text : String) -> Unit raise ReportError {
  let stack : Array[JsonContainer] = []
  let mut i = 0
  while i < text.length() {
    match text.code_unit_at(i).to_int() {
      123 => {
        stack.push(ObjectKeys({}))
        i += 1
      }
      91 => {
        stack.push(ListValue)
        i += 1
      }
      125 | 93 => {
        ignore(stack.pop())
        i += 1
      }
      34 => {
        let start = i
        i += 1
        while i < text.length() {
          if text.code_unit_at(i) == 92 {
            i += 2
          } else if text.code_unit_at(i) == 34 {
            i += 1
            break
          } else {
            i += 1
          }
        }
        let mut next = i
        while next < text.length() &&
              (
                text.code_unit_at(next) == 32 ||
                text.code_unit_at(next) == 9 ||
                text.code_unit_at(next) == 10 ||
                text.code_unit_at(next) == 13
              ) {
          next += 1
        }
        if next < text.length() &&
          text.code_unit_at(next) == 58 &&
          !stack.is_empty() {
          match stack[stack.length() - 1] {
            ObjectKeys(keys) => {
              let key = @json.parse(text[start:i]) catch {
                _ => raise InvalidReport("Malformed object key.")
              }
              match key {
                String(key) => {
                  if keys.contains(key) {
                    raise InvalidReport("Duplicate JSON key: \{key}")
                  }
                  keys[key] = true
                }
                _ => raise InvalidReport("Invalid object key.")
              }
            }
            ListValue => ()
          }
        }
      }
      _ => i += 1
    }
  }
}

///|
/// Decode a report by replaying its retained SQL and execution context. Unknown
/// fields, duplicate members and altered/omitted derived diagnostics are rejected.
/// This is integrity-by-recomputation, not authentication or a digital signature.
pub fn decode_report(text : String) -> Review raise ReportError {
  if text.length() > 8388608 {
    raise InvalidReport("Report exceeds the 8 Mi UTF-16 code-unit limit.")
  }
  let value = @json.parse(text) catch {
    _ => raise InvalidReport("Malformed JSON report.")
  }
  reject_duplicate_keys(text)
  match value {
    {
      "format": String("moonddl.review.v1"),
      "source": String(source),
      "transaction": transaction,
      "delivery": delivery,
      ..
    } => {
      let transaction : Transaction = match transaction {
        String("Autocommit") => Autocommit
        String("Active") => Active
        String("UnknownTransaction") => UnknownTransaction
        _ => raise InvalidReport("Unknown transaction state.")
      }
      let delivery : Delivery = match delivery {
        String("PerStatement") => PerStatement
        String("SimpleQuery") => SimpleQuery
        String("UnknownDelivery") => UnknownDelivery
        _ => raise InvalidReport("Unknown delivery mode.")
      }
      let review = review_sql(source, transaction~, delivery~)
      if review.to_json() != value {
        raise InvalidReport(
          "Unknown fields, missing fields or findings inconsistent with this rule profile; regenerate the report.",
        )
      }
      review
    }
    _ =>
      raise InvalidReport(
        "Expected a moonddl.review.v1 report with source and execution context.",
      )
  }
}
