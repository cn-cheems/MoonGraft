///|
/// Refuse actual output changes at exact protected paths or beneath directory
/// rules ending in '/'. Rules use portable paths and ASCII case-insensitive
/// matching. A directory rule also protects replacement by a same-named file.
pub fn Plan::check_protected(
  self : Plan,
  rules : Array[String],
) -> Unit raise GraftError {
  guard rules.length() <= 2048 else {
    raise LimitExceeded("more than 2048 protected path rules")
  }
  let normalized = []
  for rule in rules {
    let directory = rule.has_suffix("/")
    let path = if directory {
      rule[:rule.length() - 1].to_owned()
    } else {
      rule
    }
    validate_path(path)
    normalized.push((path.to_lower(), directory))
  }
  let reasons = []
  for change in self.output_changes() {
    let path = match change {
      Added(path, _, _) | Removed(path, _, _) | Modified(path, _, _, _, _, _) =>
        path
    }
    let lower = path.to_lower()
    if normalized.any(rule => {
        lower == rule.0 || (rule.1 && lower.has_prefix(rule.0 + "/"))
      }) {
      reasons.push("protected path would change: " + path)
    }
  }
  guard reasons.is_empty() else { raise PolicyRejected(reasons) }
}

///|
/// Strict versioned rule-file reader. Rule validation is identical to the API.
pub fn Plan::check_protected_json(
  self : Plan,
  source : String,
) -> Unit raise GraftError {
  guard open_archive(source, "moongraft.protected") is Array(values) else {
    raise InvalidArchive("expected protected path array")
  }
  guard values.length() <= 2048 else {
    raise LimitExceeded("more than 2048 protected path rules")
  }
  let rules = values.map(value => {
    guard value is String(path) else {
      raise InvalidArchive("protected path must be a string")
    }
    path
  })
  self.check_protected(rules)
}
