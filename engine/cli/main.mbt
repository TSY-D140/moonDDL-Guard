///|
fn main {
  let args = process_args()
  if args.length() == 2 && args[1] == "--help" {
    println(
      "Usage: moon run engine/cli -- FILE [--json] [--replay] [--transaction=autocommit|active|unknown] [--delivery=statements|simple-query|unknown]",
    )
    println(
      "Defaults: unknown transaction and delivery. PostgreSQL 18 rules. Exit 0: no blocking finding; 1: risk; 2: incomplete/input error.",
    )
    return
  }
  if args.length() < 2 {
    println("Missing SQL file. Run with --help for usage.")
    @sys.exit(2)
    return
  }
  let path = args[1]
  let mut json = false
  let mut replay = false
  let mut transaction = @guard.UnknownTransaction
  let mut delivery = @guard.UnknownDelivery
  for arg in args[2:] {
    match arg {
      "--json" => json = true
      "--replay" => replay = true
      "--transaction=autocommit" => transaction = @guard.Autocommit
      "--transaction=active" => transaction = @guard.Active
      "--transaction=unknown" => transaction = @guard.UnknownTransaction
      "--delivery=statements" => delivery = @guard.PerStatement
      "--delivery=simple-query" => delivery = @guard.SimpleQuery
      "--delivery=unknown" => delivery = @guard.UnknownDelivery
      _ => {
        println("Unknown option: \{arg}")
        @sys.exit(2)
        return
      }
    }
  }
  try @utf8.decode(@fs.read_file_to_bytes(path)) catch {
    _ => {
      println("Cannot read UTF-8 SQL file: \{path}")
      @sys.exit(2)
    }
  } noraise {
    sql => {
      let review = if replay {
        if transaction != @guard.UnknownTransaction ||
          delivery != @guard.UnknownDelivery {
          println(
            "Replay uses the recorded execution context; omit context overrides.",
          )
          @sys.exit(2)
          return
        }
        @guard.decode_report(sql) catch {
          error => {
            println("Report replay rejected: \{Repr(error)}")
            @sys.exit(2)
            return
          }
        }
      } else {
        @guard.review_sql(sql, transaction~, delivery~)
      }
      if json {
        println(review.to_json().stringify())
      } else {
        println(review.to_text())
      }
      @sys.exit(review.exit_code())
    }
  }
}
