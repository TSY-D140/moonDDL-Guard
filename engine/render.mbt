///|
pub fn Review::to_json(self : Review) -> Json {
  {
    "format": "moonddl.review.v1",
    "postgres": 18,
    "source": self.source,
    "transaction": self.transaction.to_json(),
    "delivery": self.delivery.to_json(),
    "complete": self.is_complete(),
    "exit_code": self.exit_code(),
    "statements": self.statements.to_json(),
    "findings": self.findings.to_json(),
  }
}

///|
pub fn Review::to_text(self : Review) -> String {
  let output = StringBuilder()
  output.write_string(
    "PostgreSQL 18 index preflight: \{self.statements.length()} statements; complete=\{self.is_complete()}; exit=\{self.exit_code()}\n",
  )
  for f in self.findings {
    output.write_string(
      "\{f.code} [\{Repr(f.severity)}] statement \{f.statement} at \{f.location.line}:\{f.location.column}: \{f.message}\n  Next: \{f.action}\n",
    )
  }
  output.write_string(
    "Static findings only; database state and production safety are not verified.\n",
  )
  output.to_string()
}
