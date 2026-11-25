///|
/// A maintainer-declared movement of one template file between two revisions.
pub struct FileRename {
  from_path : String
  to_path : String
} derive(Debug, Eq)

///|
pub fn FileRename::new(from_path : String, to_path : String) -> FileRename {
  { from_path, to_path, }
}

///|
/// Decode a versioned list of explicit file moves.
pub fn FileRename::decode_list(
  source : String,
) -> Array[FileRename] raise GraftError {
  parse_renames(open_archive(source, "moongraft.renames"))
}

///|
fn parse_renames(payload : Json) -> Array[FileRename] raise GraftError {
  guard payload is Array(rows) else {
    raise InvalidArchive("expected an array of [old-path, new-path] pairs")
  }
  guard rows.length() <= 2048 else {
    raise LimitExceeded("more than 2048 file moves")
  }
  rows.map(row => {
    guard row is Array([String(from_path), String(to_path)]) else {
      raise InvalidArchive("expected a file move [old-path, new-path]")
    }
    FileRename::new(from_path, to_path)
  })
}

///|
fn rename_rows(renames : Array[FileRename]) -> Json {
  Json::array(
    renames.map(rename => {
      Json::array([Json::string(rename.from_path), Json::string(rename.to_path)])
    }),
  )
}

///|
fn align_renames(
  baseline : Tree,
  current : Tree,
  next : Tree,
  renames : Array[FileRename],
) -> (Array[FileRename], Tree, Tree) raise GraftError {
  if renames.is_empty() {
    return ([], baseline, current)
  }
  guard renames.length() <= 2048 else {
    raise LimitExceeded("more than 2048 file moves")
  }
  let mappings = renames.copy()
  mappings.sort_by((a, b) => a.from_path.lexical_compare(b.from_path))
  let destinations : Map[String, String] = Map([])
  let sources : Map[String, String] = Map([])
  for rename in mappings {
    let { from_path, to_path, } = rename
    validate_path(from_path)
    validate_path(to_path)
    guard from_path != to_path &&
      baseline.get(from_path) is Some(_) &&
      next.get(from_path) is None &&
      baseline.get(to_path) is None &&
      next.get(to_path) is Some(_) else {
      raise InvalidTemplate(
        "Invalid file move '" +
        from_path +
        "' -> '" +
        to_path +
        "': source must belong only to the old template and destination only to the new template",
      )
    }
    let folded = to_path.to_lower()
    guard !sources.contains(from_path) && !destinations.contains(folded) else {
      raise InvalidTemplate(
        "File moves must be one-to-one: '" +
        from_path +
        "' -> '" +
        to_path +
        "'",
      )
    }
    // An independently added destination would otherwise be mistaken for the
    // local version of the moved template file, even if its bytes match.
    guard !current.entries.any(file => {
      file.path != from_path && file.path.to_lower() == folded
    }) else {
      raise InvalidTemplate(
        "Project already occupies file move destination '" + to_path + "'",
      )
    }
    sources[from_path] = to_path
    destinations[folded] = from_path
  }
  fn align(tree : Tree) -> Tree raise GraftError {
    Tree::new(
      tree.entries.map(file => {
        match sources.get(file.path) {
          Some(path) => { ..file, path, }
          None => file
        }
      }),
    )
  }
  (mappings, align(baseline), align(current))
}
