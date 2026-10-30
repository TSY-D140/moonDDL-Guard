name = "TSY-D140/moonddl_guard"

version = "0.15.0"

source = "engine"

readme = "README.md"

repository = "https://github.com/TSY-D140/moonDDL-Guard"

license = "Apache-2.0"

keywords = [ "postgresql", "migration", "index", "preflight", "ci" ]

preferred_target = "wasm"

description = "Execution-aware PostgreSQL migration preflight"

import {
  "bobzhang/sqlglot@0.1.0",
  "moonbitlang/x@0.5.5",
}
