///|
/// Enforce limits against the actual output, including resolved custom files.
/// Growth is net content bytes; binary changes include additions/removals and
/// mode-only changes to a binary file. Limits must be nonnegative.
pub fn Plan::check_policy(
  self : Plan,
  max_removed~ : Int32,
  max_binary_changes~ : Int32,
  max_growth_bytes~ : Int32,
) -> Unit raise GraftError {
  guard max_removed >= 0 && max_binary_changes >= 0 && max_growth_bytes >= 0 else {
    raise InvalidDecision("<policy>", "all limits must be nonnegative")
  }
  let result = self.materialize()
  let mut removed = 0
  let mut binary = 0
  let mut growth = 0
  for path in all_paths([self.current, result]) {
    let before = self.current.get(path)
    let after = result.get(path)
    if before == after {
      continue
    }
    if before is Some(file) {
      growth -= file.content.length()
    }
    if after is Some(file) {
      growth += file.content.length()
    } else {
      removed += 1
    }
    let binary_before = match before {
      Some(file) => !is_text(file.content)
      None => false
    }
    let binary_after = match after {
      Some(file) => !is_text(file.content)
      None => false
    }
    if binary_before || binary_after {
      binary += 1
    }
  }
  let reasons = []
  if removed > max_removed {
    reasons.push("removed files \{removed} exceeds \{max_removed}")
  }
  if binary > max_binary_changes {
    reasons.push("binary changes \{binary} exceeds \{max_binary_changes}")
  }
  if growth > max_growth_bytes {
    reasons.push("net growth \{growth} bytes exceeds \{max_growth_bytes}")
  }
  guard reasons.is_empty() else { raise PolicyRejected(reasons) }
}
