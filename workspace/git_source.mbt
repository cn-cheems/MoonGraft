///|
/// A local Git source, selected subtree, and recorded template baseline.
pub struct GitSource {
  repository : String
  subdir : String
  baseline : @graft.Baseline
}

///|
fn require_git_sha(revision : String) -> Unit raise WorkspaceError {
  guard revision.length() == 40 &&
    revision.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) else {
    raise WorkspaceError(
      "Expected a full lowercase 40-character Git commit SHA",
    )
  }
}

///|
fn git_source_id(repository : String, subdir : String) -> String {
  Json::array([Json::string(repository), Json::string(subdir)]).stringify()
}

///|
pub fn GitSource::encode(self : GitSource) -> String {
  Json::array([
    Json::string("moongraft.git-source.v1"),
    Json::string(self.repository),
    Json::string(self.subdir),
    Json::string(self.baseline.encode()),
  ]).stringify()
}

///|
pub fn GitSource::decode(text : String) -> GitSource raise {
  guard @json.parse(text)
    is Array(
      [
        String("moongraft.git-source.v1"),
        String(repository),
        String(subdir),
        String(raw),
      ]
    ) else {
    raise WorkspaceError("Expected a moongraft.git-source.v1 record")
  }
  if !subdir.is_empty() {
    ignore(@graft.File::new(subdir, b""))
  }
  let baseline = @graft.Baseline::decode(raw)
  require_git_sha(baseline.revision)
  guard baseline.template_id == git_source_id(repository, subdir) else {
    raise WorkspaceError("Git source and recorded baseline identity differ")
  }
  { repository, subdir, baseline, }
}

///|
async fn git_read(
  repository : String,
  args : Array[String],
  limit : Int32,
) -> Bytes {
  let output = @shell.Cmd(
    "git",
    ["--no-replace-objects", "--literal-pathspecs", "-C", repository] + args,
    env={ "GIT_NO_LAZY_FETCH": "1" },
  ).output(timeout_ms=10000, max_output_bytes=limit)
  guard output.exit_code() == 0 else {
    raise WorkspaceError(
      "Git " + args[0] + " failed: " + output.stderr().trim().to_owned(),
    )
  }
  output.stdout_bytes()
}

///|
/// Read committed blobs directly. The working tree, attributes, and hooks are
/// never used for rendering.
pub async fn capture_git_source(
  repository : String,
  revision : String,
  subdir : String,
) -> GitSource {
  require_git_sha(revision)
  if !subdir.is_empty() {
    ignore(@graft.File::new(subdir, b""))
  }
  let repository = @fs.realpath(repository).replace_all(old="\\", new="/")
  let kind = @utf8.decode(
    git_read(repository, ["cat-file", "-t", revision], 4096),
  )
  guard kind.trim() == "commit" else {
    raise WorkspaceError("Git revision must identify a commit: " + revision)
  }
  let args = ["ls-tree", "-r", "-z", "--full-tree", revision]
  if !subdir.is_empty() {
    args.push("--")
    args.push(subdir + "/")
  }
  let entries = @utf8.decode(
    git_read(repository, args, 2097152),
    ignore_bom=false,
  )
  let files = []
  let mut remaining = 16777216
  let prefix = if subdir.is_empty() { "" } else { subdir + "/" }
  for entry in entries.split("\u{0000}") {
    if entry.is_empty() {
      continue
    }
    guard entry.split_once("\t") is Some((header, path)) &&
      header.split(" ").to_array() is [mode, "blob", oid] &&
      (mode == "100644" || mode == "100755") &&
      path.has_prefix(prefix) else {
      raise WorkspaceError("Unsupported Git tree entry: " + entry.to_owned())
    }
    let logical = path[prefix.length():].to_owned()
    let executable = mode == "100755"
    ignore(@graft.File::new(logical, b"", executable~))
    guard files.length() < 2048 else {
      raise WorkspaceError("Git template exceeds 2048 files")
    }
    let limit = Int32::min(2097152, remaining)
    let content = git_read(
      repository,
      ["cat-file", "blob", oid.to_owned()],
      limit + 1,
    ) catch {
      error =>
        raise WorkspaceError(
          "Cannot read Git template blob within its byte limit: " +
          logical +
          " (" +
          error.to_string() +
          ")",
        )
    }
    guard content.length() <= limit else {
      raise WorkspaceError(
        "Git template blob exceeds its byte limit: " + logical,
      )
    }
    remaining -= content.length()
    files.push(@graft.File::new(logical, content, executable~))
  }
  guard !files.is_empty() else {
    raise WorkspaceError(
      "Git template contains no files in the selected directory: " + subdir,
    )
  }
  let tree = @graft.Tree::new(files)
  {
    repository,
    subdir,
    baseline: @graft.track(git_source_id(repository, subdir), revision, tree),
  }
}

///|
/// Generate a project from the pinned baseline into a new verified export.
pub async fn GitSource::create_project(
  self : GitSource,
  destination : String,
) -> Unit {
  require_outside(destination, self.repository)
  let baseline = self.baseline
  let plan = @graft.plan_update(baseline, baseline.tree, baseline)
  export_result(plan.apply(baseline.tree), destination)
}

///|
/// Read an explicit target revision from the same source and subtree.
pub async fn GitSource::at(self : GitSource, revision : String) -> GitSource {
  let target = capture_git_source(self.repository, revision, self.subdir)
  guard target.baseline.template_id == self.baseline.template_id else {
    raise WorkspaceError(
      "Git source location changed; capture a new source record explicitly",
    )
  }
  target
}

///|
/// Plan an upgrade against a commit from the recorded source.
pub async fn GitSource::plan_upgrade(
  self : GitSource,
  current : @graft.Tree,
  revision : String,
) -> @graft.Plan {
  let target = self.at(revision)
  @graft.plan_update(self.baseline, current, target.baseline)
}

///|
/// Advance the record after verifying the resolved candidate and both baselines.
pub async fn GitSource::accept_upgrade(
  self : GitSource,
  plan : @graft.Plan,
  accepted : @graft.Tree,
) -> GitSource {
  let original = plan.rollback(accepted) catch {
    @graft.StaleProject =>
      raise WorkspaceError(
        "Accepted project differs from the resolved candidate; source record was not advanced",
      )
    error => raise error
  }
  guard original.baseline == self.baseline else {
    raise WorkspaceError("Plan starts from a different template baseline")
  }
  let next = plan.next_baseline()
  let target = self.at(next.revision)
  guard target.baseline == next else {
    raise WorkspaceError("Plan target differs from the pinned Git template")
  }
  target
}
