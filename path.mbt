///|
fn validate_path(path : String) -> Unit raise GraftError {
  guard !path.is_empty() && path.length() <= 240 else {
    raise InvalidPath(path, "expected 1–240 ASCII characters")
  }
  for c in path {
    let code = c.to_int()
    guard code >= 32 && code < 127 && !"\\:*?\"<>|".contains(c.to_string()) else {
      raise InvalidPath(
        path, "use a portable ASCII relative path with '/' separators",
      )
    }
  }
  for part in path.split("/") {
    guard !part.is_empty() &&
      part != "." &&
      part != ".." &&
      !part.has_suffix(".") &&
      !part.has_suffix(" ") else {
      raise InvalidPath(
        path, "empty, dot, traversal, and trailing-dot/space segments are forbidden",
      )
    }
    let lower = part.to_owned().to_lower()
    guard lower != ".git" else {
      raise InvalidPath(path, "Git metadata is outside the managed tree")
    }
    let stem = lower.split(".").to_array()[0].to_owned()
    guard ![
      "con", "prn", "aux", "nul", "conin$", "conout$", "com1", "com2", "com3", "com4",
      "com5", "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5",
      "lpt6", "lpt7", "lpt8", "lpt9",
    ].contains(stem) else {
      raise InvalidPath(path, "Windows device names are not portable")
    }
  }
}
