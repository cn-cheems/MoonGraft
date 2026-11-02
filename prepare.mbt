///|
fn policy_limit(value : Json) -> Int32 raise GraftError {
  guard value is Number(number, ..) && number >= 0.0 && number <= 2147483647.0 else {
    raise InvalidArchive("policy limits must be nonnegative 32-bit integers")
  }
  let limit : Int32 = @json.from_json(value) catch {
    _ =>
      raise InvalidArchive("policy limits must be nonnegative 32-bit integers")
  }
  guard limit >= 0 && limit.to_double() == number else {
    raise InvalidArchive("policy limits must be integers")
  }
  limit
}

///|
/// Bind snapshot validation, resource policy and protected paths to one immutable
/// plan before returning an exportable result. No filesystem writes occur here.
pub fn Plan::prepare(
  self : Plan,
  current : Tree,
  policy : String,
) -> Applied raise GraftError {
  guard current == self.current else { raise StaleProject }
  guard open_archive(policy, "moongraft.policy")
    is Array([removed, binary, growth, Array(paths)]) else {
    raise InvalidArchive(
      "expected policy [max-removed, max-binary-changes, max-growth-bytes, protected-paths]",
    )
  }
  guard paths.length() <= 2048 else {
    raise LimitExceeded("more than 2048 protected path rules")
  }
  let rules = paths.map(value => {
    guard value is String(path) else {
      raise InvalidArchive("protected path must be a string")
    }
    path
  })
  self.check_policy(
    max_removed=policy_limit(removed),
    max_binary_changes=policy_limit(binary),
    max_growth_bytes=policy_limit(growth),
  )
  self.check_protected(rules)
  self.apply(current)
}
