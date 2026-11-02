///|
/// Errors are actionable and never indicate that unsupported input was skipped.
pub(all) suberror GraftError {
  InvalidPath(String, String)
  LimitExceeded(String)
  InvalidArchive(String)
  InvalidTemplate(String)
  InvalidDecision(String, String)
  Unresolved(Array[String])
  StaleProject
  PolicyRejected(Array[String])
  StructuralCollision(String, String)
} derive(Debug)

///|
pub fn GraftError::message(self : GraftError) -> String {
  match self {
    InvalidPath(path, why) => "Invalid path '\{path}': \{why}"
    LimitExceeded(why) => "Resource limit exceeded: \{why}"
    InvalidArchive(why) => "Invalid MoonGraft archive: \{why}"
    InvalidTemplate(why) => "Invalid template identity: \{why}"
    InvalidDecision(path, why) => "Invalid decision for '\{path}': \{why}"
    Unresolved(paths) =>
      "Resolve these conflicts before applying: " + paths.join(", ")
    StaleProject =>
      "The project changed after planning; generate and review a new plan."
    PolicyRejected(reasons) => "Upgrade policy rejected: " + reasons.join("; ")
    StructuralCollision(a, b) =>
      "Paths '\{a}' and '\{b}' cannot coexist; revise the template or conflict decisions."
  }
}

///|
/// An ordinary file. Contents are immutable bytes; no lossy text conversion.
pub struct File {
  path : String
  content : Bytes
  executable : Bool
} derive(Debug, Eq)

///|
pub fn File::new(
  path : String,
  content : Bytes,
  executable~ : Bool = false,
) -> File raise GraftError {
  validate_path(path)
  guard content.length() <= 2097152 else {
    raise LimitExceeded("file '\{path}' exceeds 2 MiB")
  }
  { path, content, executable, }
}

///|
/// Convenience constructor; text is UTF-8 encoded, with no newline normalization.
pub fn File::text(
  path : String,
  content : String,
  executable~ : Bool = false,
) -> File raise GraftError {
  File::new(path, @utf8.encode(content), executable~)
}

///|
/// A validated, portable, immutable tree of regular files.
pub struct Tree {
  priv entries : Array[File]
} derive(Debug, Eq)

///|
/// Files are copied and sorted; duplicate, case-colliding and file/directory
/// colliding paths are rejected. Empty directories are outside this model.
pub fn Tree::new(files : Array[File]) -> Tree raise GraftError {
  guard files.length() <= 2048 else {
    raise LimitExceeded("more than 2048 files")
  }
  let entries = files.copy()
  entries.sort_by((a, b) => a.path.lexical_compare(b.path))
  let seen : Map[String, String] = Map([])
  let directories : Map[String, String] = Map([])
  let mut total = 0
  for file in entries {
    validate_path(file.path)
    guard file.content.length() <= 2097152 else {
      raise LimitExceeded("file '\{file.path}' exceeds 2 MiB")
    }
    total += file.content.length()
    guard total <= 16777216 else { raise LimitExceeded("tree exceeds 16 MiB") }
    let key = file.path.to_lower()
    if seen.get(key) is Some(previous) {
      raise StructuralCollision(previous, file.path)
    }
    seen[key] = file.path
    let parts = key.split("/").to_array()
    let mut prefix = ""
    for i in 0..<(parts.length() - 1) {
      prefix = if i == 0 {
        parts[i].to_owned()
      } else {
        prefix + "/" + parts[i].to_owned()
      }
      directories[prefix] = file.path
    }
  }
  for key, path in seen {
    if directories.get(key) is Some(child) {
      raise StructuralCollision(path, child)
    }
  }
  // Differently cased directory spellings also fail, even for different files.
  let spellings : Map[String, String] = Map([])
  for file in entries {
    let parts = file.path.split("/").to_array()
    let mut prefix = ""
    for i in 0..<(parts.length() - 1) {
      prefix = if i == 0 {
        parts[i].to_owned()
      } else {
        prefix + "/" + parts[i].to_owned()
      }
      let key = prefix.to_lower()
      if spellings.get(key) is Some(old) && old != prefix {
        raise StructuralCollision(old, prefix)
      }
      spellings[key] = prefix
    }
  }
  Tree::{ entries, }
}

///|
pub fn Tree::files(self : Tree) -> Array[File] {
  self.entries.copy()
}

///|
pub fn Tree::get(self : Tree, path : String) -> File? {
  for file in self.entries {
    if file.path == path {
      return Some(file)
    }
  }
  None
}

///|
/// Explicit provenance for a rendered template, rather than inferred ownership.
pub struct Baseline {
  template_id : String
  revision : String
  tree : Tree
} derive(Debug, Eq)

///|
pub fn track(
  template_id : String,
  revision : String,
  tree : Tree,
) -> Baseline raise GraftError {
  for value in [template_id, revision] {
    guard !value.trim().is_empty() && value.length() <= 1024 else {
      raise InvalidTemplate(
        "template identifier and revision must contain 1–1024 characters",
      )
    }
    for c in value {
      guard c.to_int() >= 32 && c != '\u{007f}' else {
        raise InvalidTemplate(
          "identifier and revision cannot contain control characters",
        )
      }
    }
  }
  { template_id, revision, tree, }
}

///|
pub(all) enum ConflictReason {
  BothAdded
  BothModified
  TemplateDeleted
  ProjectDeleted
  TextMergeLimit
} derive(Debug, Eq)

///|
pub(all) enum ChangeKind {
  Unchanged
  KeptLocal
  TookTemplate
  Merged
  Conflict(ConflictReason)
} derive(Debug, Eq)

///|
pub struct Change {
  path : String
  kind : ChangeKind
} derive(Debug, Eq)

///|
/// The three original file versions for an explicit conflict review.
pub struct ConflictDetail {
  reason : ConflictReason
  base : File?
  project : File?
  template : File?
} derive(Debug, Eq)

///|
pub(all) enum Resolution {
  KeepLocal
  TakeTemplate
  Replace(File)
  Delete
} derive(Debug, Eq)

///|
pub struct Decision {
  path : String
  resolution : Resolution
} derive(Debug, Eq)

///|
pub fn Decision::new(path : String, resolution : Resolution) -> Decision {
  { path, resolution, }
}

///|
pub struct Plan {
  priv baseline : Baseline
  priv current : Tree
  priv next : Baseline
  priv changes : Array[Change]
  priv decisions : Array[Decision]
} derive(Debug, Eq)

///|
pub fn Plan::changes(self : Plan) -> Array[Change] {
  self.changes.copy()
}

///|
pub fn Plan::decisions(self : Plan) -> Array[Decision] {
  self.decisions.copy()
}

///|
pub fn Plan::conflicts(self : Plan) -> Array[Change] {
  self.changes.filter(change => change.kind is Conflict(_))
}

///|
pub fn Plan::next_baseline(self : Plan) -> Baseline {
  self.next
}

///|
/// A complete result and the next template baseline. The baseline remains the
/// rendered template, not the locally customized output.
pub struct Applied {
  tree : Tree
  baseline : Baseline
} derive(Debug, Eq)
