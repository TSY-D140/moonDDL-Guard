///|
// Exact decimal arithmetic only: a value requiring sub-millisecond rounding
// remains unassessed rather than being silently rounded to zero (disabled).
fn timeout_duration(input : String) -> TimeoutValue {
  let value = input.trim().to_owned()
  if value.is_empty() || value.length() > 64 {
    return Unrepresentable
  }
  for ch in input {
    if ch.to_int() > 127 {
      return Unrepresentable
    }
  }
  let limit : Int64 = 2147483647
  let mut i = 0
  let mut whole : Int64 = 0
  let mut digits = 0
  while i < value.length() {
    let digit = value.code_unit_at(i).to_int() - 48
    if digit < 0 || digit > 9 {
      break
    }
    if whole > (limit - digit.to_int64()) / 10 {
      return Unrepresentable
    }
    whole = whole * 10 + digit.to_int64()
    digits += 1
    i += 1
  }
  // PostgreSQL accepts octal integers: do not silently read 010 as decimal 10.
  if digits > 1 && value.code_unit_at(0) == 48 {
    return Unrepresentable
  }
  let mut fraction : Int64 = 0
  let mut scale : Int64 = 1
  if i < value.length() && value.code_unit_at(i) == 46 {
    i += 1
    let mut fractional_digits = 0
    while i < value.length() {
      let digit = value.code_unit_at(i).to_int() - 48
      if digit < 0 || digit > 9 {
        break
      }
      if fractional_digits == 6 {
        return Unrepresentable
      }
      fraction = fraction * 10 + digit.to_int64()
      scale *= 10
      fractional_digits += 1
      digits += 1
      i += 1
    }
    if fractional_digits == 0 {
      return Unrepresentable
    }
  }
  if digits == 0 {
    return Unrepresentable
  }
  let (multiplier, quantum) : (Int64, Int64) = match
    value[i:].trim().to_owned() {
    "" | "ms" => (1, 1)
    "s" => (1000, 1)
    "min" => (60000, 1000)
    "h" => (3600000, 60000)
    "d" => (86400000, 3600000)
    _ => return Unrepresentable
  }
  if whole > limit / multiplier {
    return Unrepresentable
  }
  let fractional_ms = fraction * multiplier
  if fractional_ms % scale != 0 {
    return Unrepresentable
  }
  let result = whole * multiplier + fractional_ms / scale
  // PostgreSQL first rounds to the next smaller unit. Accept only inputs
  // unchanged by that conversion and the final integer-millisecond rounding.
  if result > limit || result % quantum != 0 {
    return Unrepresentable
  }
  Milliseconds(result)
}

///|
priv struct TimeoutSetting {
  parameter : String
  scoped : Bool
  value : TimeoutValue
}

///|
fn timeout_setting(tokens : Array[@syntax.Token]) -> TimeoutSetting? {
  if !word(tokens, 0, "SET") {
    return None
  }
  let mut i = 1
  let scoped = word(tokens, i, "LOCAL")
  if scoped || word(tokens, i, "SESSION") {
    i += 1
  }
  let parameter = if word(tokens, i, "LOCK_TIMEOUT") {
    "lock_timeout"
  } else if word(tokens, i, "STATEMENT_TIMEOUT") {
    "statement_timeout"
  } else {
    return None
  }
  i += 1
  let mut value = Unrepresentable
  if i < tokens.length() &&
    (tokens[i].token_type == @syntax.EQ || word(tokens, i, "TO")) {
    i += 1
    if i + 1 == tokens.length() {
      value = if word(tokens, i, "DEFAULT") {
        UnknownTimeout
      } else if tokens[i].token_type == @syntax.STRING ||
        tokens[i].token_type == @syntax.NUMBER {
        timeout_duration(tokens[i].text)
      } else {
        Unrepresentable
      }
    }
  }
  Some({ parameter, scoped, value, })
}
