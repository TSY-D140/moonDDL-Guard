///|
fn main {
  let args = process_args()
  if args.length() == 2 && args[1] == "--help" {
    println(
      "Usage: moon run engine/cli -- FILE [--json|--sarif] [--artifact=REPO_PATH] [--baseline=REPORT] [--replay] [--transaction=autocommit|active|unknown] [--delivery=statements|simple-query|unknown]",
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
  let mut sarif = false
  let mut artifact : String? = None
  let mut replay = false
  let mut baseline_path : String? = None
  let mut transaction = @guard.UnknownTransaction
  let mut delivery = @guard.UnknownDelivery
  for arg in args[2:] {
    match arg {
      "--json" => json = true
      "--sarif" => sarif = true
      option if option.has_prefix("--artifact=") =>
        artifact = Some(option[11:].to_owned())
      "--replay" => replay = true
      option if option.has_prefix("--baseline=") =>
        baseline_path = Some(option[11:].to_owned())
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
  if sarif && baseline_path is Some(_) {
    println(
      "SARIF cannot be combined with --baseline; use --json or text for comparison output.",
    )
    @sys.exit(2)
    return
  }
  if (json && sarif) ||
    (artifact is Some(_) && !sarif) ||
    (replay && sarif && artifact is None) {
    println(
      "Choose one format; --artifact requires --sarif and is mandatory for SARIF replay.",
    )
    @sys.exit(2)
    return
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
      if baseline_path is Some(baseline_file) {
        let baseline_text = @utf8.decode(@fs.read_file_to_bytes(baseline_file)) catch {
          _ => {
            println("Cannot read UTF-8 baseline report: " + baseline_file)
            @sys.exit(2)
            return
          }
        }
        let baseline = @guard.decode_report(baseline_text) catch {
          error => {
            println("Baseline replay rejected: \{Repr(error)}")
            @sys.exit(2)
            return
          }
        }
        let delta = @guard.compare_reviews(baseline, review) catch {
          error => {
            println("Baseline comparison rejected: \{Repr(error)}")
            @sys.exit(2)
            return
          }
        }
        if json {
          println(delta.to_json().stringify())
        } else {
          println(delta.to_text())
        }
        @sys.exit(delta.exit_code())
        return
      }
      if sarif {
        let value = review.to_sarif(artifact.unwrap_or(path)) catch {
          error => {
            println("SARIF export rejected: \{Repr(error)}")
            @sys.exit(2)
            return
          }
        }
        println(value.stringify())
      } else if json {
        println(review.to_json().stringify())
      } else {
        println(review.to_text())
      }
      @sys.exit(review.exit_code())
    }
  }
}
