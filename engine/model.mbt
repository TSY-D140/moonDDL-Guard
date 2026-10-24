///|
/// Transaction state at the start of a migration, supplied by its runner.
pub(all) enum Transaction {
  Autocommit
  Active
  UnknownTransaction
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// How the runner submits the migration to PostgreSQL.
pub(all) enum Delivery {
  PerStatement
  SimpleQuery
  UnknownDelivery
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) enum Severity {
  Error
  Warning
  Advisory
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) enum Coverage {
  Analyzed
  Unsupported
  Invalid
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Source coordinates: zero-based UTF-16 offsets, one-based line and column.
pub(all) struct Location {
  start : Int
  end : Int
  line : Int
  column : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct Finding {
  code : String
  severity : Severity
  statement : Int
  location : Location
  message : String
  action : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct Statement {
  number : Int
  location : Location
  sql : String
  coverage : Coverage
  operation : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// A bounded static review, never a certificate of production safety.
pub struct Review {
  source : String
  transaction : Transaction
  delivery : Delivery
  statements : Array[Statement]
  findings : Array[Finding]
} derive(Eq, Debug)

///|
pub fn Review::statements(self : Review) -> Array[Statement] {
  self.statements.copy()
}

///|
pub fn Review::findings(self : Review) -> Array[Finding] {
  self.findings.copy()
}

///|
pub fn Review::is_complete(self : Review) -> Bool {
  self.statements.iter().all(s => s.coverage == Analyzed) &&
  !self.findings.iter().any(f => f.code == "PG000" || f.code == "PG002")
}

///|
/// 2 = invalid/incomplete input; 1 = known risk; 0 = no known blocking finding.
/// Advisory findings can remain at exit 0 and must still be read.
pub fn Review::exit_code(self : Review) -> Int {
  if !self.is_complete() {
    2
  } else if self.findings.iter().any(f => f.severity != Advisory) {
    1
  } else {
    0
  }
}
