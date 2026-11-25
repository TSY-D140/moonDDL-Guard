///|
// Node includes its own executable before the script name.
fn process_args() -> Array[String] {
  @env.args()[1:].to_owned()
}

///|
// Let Node drain stdout pipes before exiting; process.exit can truncate JSON.
extern "js" fn finish_cli(code : Int32) -> Unit =
  #| (code) => { process.exitCode = code; }
