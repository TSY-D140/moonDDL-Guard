# Sources and licenses

## Runtime dependencies

- `bobzhang/sqlglot@0.1.0`: SQL tokenization and parsing, MIT. https://github.com/bobzhang/sqlglot.mbt . It is a MoonBit port of SQLGlot; its upstream notices remain in the dependency distribution. No parser source is copied into this repository.
- `moonbitlang/x@0.5.5`: file access and process exit for the CLI, Apache-2.0. https://github.com/moonbitlang/x .
- MoonBit standard library: https://github.com/moonbitlang/core ; its distribution's license applies.

## Rule references

- PostgreSQL 18 CREATE INDEX: https://www.postgresql.org/docs/18/sql-createindex.html . Ordinary index builds block writes; IF NOT EXISTS is not a definition/validity check; uniqueness is a database-state precondition.
- PostgreSQL 18 protocol: https://www.postgresql.org/docs/18/protocol-flow.html#PROTOCOL-FLOW-MULTI-STATEMENT . Execution grouping changes transaction semantics.

The rule implementation and project-owned boundary tests are written for this repository. No Squawk, Strong Migrations or Unison implementation/test source has been copied. These projects informed the demand research, not an originality or performance claim.

## Ecosystem boundary

https://github.com/kath61105/moon-schema-plan compares schema models and generates SQL; its safety model explicitly does not guarantee lock/performance behavior and its scope excludes SQL parsing. https://github.com/moonbit-community/migrate executes migrations. MoonDDL Guard adds pre-execution review of existing SQL rather than schema diff, SQL rendering, or a migration runner.

The research covered Mooncakes, GitHub, awesome-moonbit and moonbit-community. It cannot establish ecosystem uniqueness or exclude unpublished projects.
