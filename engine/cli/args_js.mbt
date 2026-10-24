///|
// Node includes its own executable before the script name.
fn process_args() -> Array[String] {
  @env.args()[1:].to_owned()
}
