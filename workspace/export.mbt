///|
fn export_intent(applied : @graft.Applied) -> String {
  Json::array([
    Json::string("moongraft.export.1"),
    Json::string(applied.tree.encode()),
    Json::string(applied.baseline.encode()),
  ]).stringify() +
  "\n"
}

///|
async fn load_intent(destination : String) -> (@graft.Tree, @graft.Baseline) {
  let value = @json.parse(
    read_text(destination + "/intent.json"),
    max_nesting_depth=4,
  )
  guard value
    is Array([String("moongraft.export.1"), String(tree), String(baseline)]) else {
    raise WorkspaceError(
      "Invalid or incomplete export intent; preserve this bundle for inspection and export to a new destination",
    )
  }
  (@graft.Tree::decode(tree), @graft.Baseline::decode(baseline))
}

///|
async fn verify_partial(
  root : String,
  relative : String,
  expected : @graft.Tree,
) -> Unit {
  let directory = if relative.is_empty() { root } else { root + "/" + relative }
  require_directory(directory)
  for name in @fs.readdir(directory, include_hidden=true, sort=true) {
    let path = if relative.is_empty() { name } else { relative + "/" + name }
    let full = root + "/" + path
    match @fs.kind(full, follow_symlink=false) {
      Directory => {
        guard expected.files().any(f => f.path.has_prefix(path + "/")) else {
          raise WorkspaceError(
            "Unexpected export directory; nothing overwritten: " + path,
          )
        }
        verify_partial(root, path, expected)
      }
      Regular => {
        guard expected.get(path) is Some(file) else {
          raise WorkspaceError(
            "Unexpected export file; nothing overwritten: " + path,
          )
        }
        guard read_bytes(full) == file.content else {
          raise WorkspaceError(
            "Existing export file differs; nothing overwritten: " + path,
          )
        }
        let executable = if windows_host() {
          false
        } else {
          @fs.can_execute(full)
        }
        guard executable == file.executable else {
          raise WorkspaceError("Executable mode differs: " + path)
        }
      }
      _ =>
        raise WorkspaceError(
          "Link or special file in export; nothing overwritten: " + path,
        )
    }
  }
}

///|
async fn verify_metadata(path : String, expected : String) -> Unit {
  if @fs.exists(path) {
    guard read_text(path) == expected else {
      raise WorkspaceError(
        "Export metadata differs; nothing overwritten: " + path,
      )
    }
  }
}

///|
async fn prepare_parents(root : String, path : String) -> Unit {
  let parts = path.split("/").map(s => s.to_owned()).to_array()
  let mut directory = root
  for i in 0..<(parts.length() - 1) {
    directory += "/" + parts[i]
    if @fs.exists(directory) {
      require_directory(directory)
    } else {
      @fs.mkdir(directory)
    }
  }
}

///|
async fn recover_scratch(destination : String, expected : @graft.Tree) -> Unit {
  let pending = destination + "/pending.json"
  let scratch = destination + "/pending.bin"
  if !@fs.exists(pending) {
    guard !@fs.exists(scratch) else {
      raise WorkspaceError(
        "Scratch file has no pending record; preserve bundle for inspection",
      )
    }
    return
  }
  let value = @json.parse(read_text(pending), max_nesting_depth=2)
  guard value is String(path) && expected.get(path) is Some(file) else {
    raise WorkspaceError(
      "Invalid pending record; preserve bundle for inspection",
    )
  }
  if @fs.exists(scratch) {
    let bytes = read_bytes(scratch)
    guard !@fs.exists(destination + "/project/" + path) &&
      file.content.has_prefix(bytes) else {
      raise WorkspaceError(
        "Pending bytes do not match the intended file; nothing removed",
      )
    }
    // This reserved scratch file is the only file recovery removes.
    @fs.remove(scratch)
  }
  @fs.remove(pending)
}

///|
/// Resume only a self-describing export bundle. Existing project files must
/// already match the intended output byte-for-byte; unknown files are refused.
/// The operation requires exclusive access and does not claim power-loss safety.
pub async fn resume_export(destination : String) -> Unit {
  require_directory(destination)
  for name in @fs.readdir(destination, include_hidden=true) {
    guard [
      "intent.json", "project", "baseline.json", "complete.json", "pending.json",
      "pending.bin",
    ].contains(name) else {
      raise WorkspaceError(
        "Unknown entry in export bundle; nothing overwritten: " + name,
      )
    }
  }
  let (tree, baseline) = load_intent(destination)
  for file in tree.files() {
    guard !windows_host() || !file.executable else {
      raise WorkspaceError(
        "Windows cannot preserve this executable-mode attribute: " + file.path,
      )
    }
  }
  let project = destination + "/project"
  if @fs.exists(project) {
    verify_partial(project, "", tree)
  }
  verify_metadata(destination + "/baseline.json", baseline.encode())
  verify_metadata(
    destination + "/complete.json",
    "[\"moongraft.complete\",\"1\"]\n",
  )
  recover_scratch(destination, tree)
  if !@fs.exists(project) {
    @fs.mkdir(project)
  }
  for file in tree.files() {
    let target = project + "/" + file.path
    if @fs.exists(target) {
      continue
    }
    prepare_parents(project, file.path)
    write_new(
      destination + "/pending.json",
      Json::string(file.path).stringify(),
    )
    let scratch = destination + "/pending.bin"
    @fs.write_file(scratch, file.content, create_mode=CreateNew)
    if !windows_host() {
      @fs.chmod(scratch, if file.executable { 0o755 } else { 0o644 })
    }
    @fs.rename(scratch, target, replace=false)
    @fs.remove(destination + "/pending.json")
  }
  guard scan(project) == tree else {
    raise WorkspaceError(
      "Export verification failed; completion marker not issued",
    )
  }
  if !@fs.exists(destination + "/baseline.json") {
    write_new(destination + "/baseline.json", baseline.encode())
  }
  if !@fs.exists(destination + "/complete.json") {
    write_new(
      destination + "/complete.json",
      "[\"moongraft.complete\",\"1\"]\n",
    )
  }
}

///|
/// Create a complete candidate project in a new directory. The source project
/// is never opened for writing. On failure use resume_export on this bundle.
pub async fn export_result(
  applied : @graft.Applied,
  destination : String,
) -> Unit {
  for file in applied.tree.files() {
    guard !windows_host() || !file.executable else {
      raise WorkspaceError(
        "Windows cannot preserve this executable-mode attribute: " + file.path,
      )
    }
  }
  @fs.mkdir(destination)
  write_new(destination + "/intent.json", export_intent(applied))
  resume_export(destination)
}
