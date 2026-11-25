///|
/// A local Git source, selected subtree, and recorded template baseline.
pub struct GitSource {
  repository : String
  subdir : String
  baseline : @graft.Baseline
  priv parameters : @graft.RenderParameters?
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
fn git_source_id(
  repository : String,
  subdir : String,
  parameters : @graft.RenderParameters?,
) -> String {
  let fields = [Json::string(repository), Json::string(subdir)]
  if parameters is Some(values) {
    fields.push(Json::string("moongraft.render.v1"))
    fields.push(Json::string(values.encode()))
  }
  Json::array(fields).stringify()
}

///|
pub fn GitSource::encode(self : GitSource) -> String {
  let fields = [
    Json::string(
      if self.parameters is Some(_) {
        "moongraft.git-source.v2"
      } else {
        "moongraft.git-source.v1"
      },
    ),
    Json::string(self.repository),
    Json::string(self.subdir),
    Json::string(self.baseline.encode()),
  ]
  if self.parameters is Some(values) {
    fields.push(Json::string("moongraft.render.v1"))
    fields.push(Json::string(values.encode()))
  }
  Json::array(fields).stringify()
}

///|
pub fn GitSource::decode(text : String) -> GitSource raise {
  let (repository, subdir, raw, parameters) = match @json.parse(text) {
    Array(
      [
        String("moongraft.git-source.v1"),
        String(repository),
        String(subdir),
        String(raw),
      ]
    ) => (repository, subdir, raw, None)
    Array(
      [
        String("moongraft.git-source.v2"),
        String(repository),
        String(subdir),
        String(raw),
        String("moongraft.render.v1"),
        String(values),
      ]
    ) =>
      (repository, subdir, raw, Some(@graft.RenderParameters::decode(values)))
    _ =>
      raise WorkspaceError(
        "Expected a supported MoonGraft Git source record and renderer version",
      )
  }
  if !subdir.is_empty() {
    ignore(@graft.File::new(subdir, b""))
  }
  let baseline = @graft.Baseline::decode(raw)
  require_git_sha(baseline.revision)
  guard baseline.template_id == git_source_id(repository, subdir, parameters) else {
    raise WorkspaceError("Git source and recorded baseline identity differ")
  }
  { repository, subdir, baseline, parameters, }
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
    baseline: @graft.track(
      git_source_id(repository, subdir, None),
      revision,
      tree,
    ),
    parameters: None,
  }
}

///|
/// Capture a pinned Git template with a deterministic, versioned render recipe.
pub async fn capture_parameterized_git_source(
  repository : String,
  revision : String,
  subdir : String,
  parameters : @graft.RenderParameters,
) -> GitSource {
  let raw = capture_git_source(repository, revision, subdir)
  let tree = raw.baseline.tree.render_parameters(parameters)
  let recipe = Some(parameters)
  let baseline = @graft.track(
    git_source_id(raw.repository, subdir, recipe),
    revision,
    tree,
  )
  { ..raw, baseline, parameters: recipe, }
}

///|
async fn GitSource::capture_at(
  self : GitSource,
  repository : String,
  revision : String,
) -> GitSource {
  match self.parameters {
    Some(values) =>
      capture_parameterized_git_source(
        repository,
        revision,
        self.subdir,
        values,
      )
    None => capture_git_source(repository, revision, self.subdir)
  }
}

///|
/// Rebuild the pinned revision and verify its exact archived template baseline.
pub async fn GitSource::verify_replay(self : GitSource) -> Unit {
  guard self.at(self.baseline.revision).baseline == self.baseline else {
    raise WorkspaceError(
      "Rebuilt Git template differs from the recorded baseline",
    )
  }
}

///|
async fn GitSource::verify_parameterized_baseline(self : GitSource) -> Unit {
  if self.parameters is Some(_) {
    self.verify_replay()
  }
}

///|
/// Generate a project from the pinned baseline into a new verified export.
pub async fn GitSource::create_project(
  self : GitSource,
  destination : String,
) -> Unit {
  require_outside(destination, self.repository)
  self.verify_parameterized_baseline()
  let baseline = self.baseline
  let plan = @graft.plan_update(baseline, baseline.tree, baseline)
  export_result(plan.apply(baseline.tree), destination)
}

///|
/// Read an explicit target revision from the same source and subtree.
pub async fn GitSource::at(self : GitSource, revision : String) -> GitSource {
  let target = self.capture_at(self.repository, revision)
  guard target.baseline.template_id == self.baseline.template_id else {
    raise WorkspaceError(
      "Git source location changed; capture a new source record explicitly",
    )
  }
  target
}

///|
/// Review how an existing project differs from a maintainer-selected baseline.
/// The project is never used to construct the baseline.
pub fn GitSource::inspect_project(
  self : GitSource,
  current : @graft.Tree,
) -> @graft.Plan raise @graft.GraftError {
  @graft.plan_update(self.baseline, current, self.baseline)
}

///|
/// Rebind a record to a local copy after verifying the pinned commit, selected
/// subtree and every baseline file. Plans must be regenerated for the new identity.
pub async fn GitSource::relocate(
  self : GitSource,
  repository : String,
) -> GitSource {
  let target = self.capture_at(repository, self.baseline.revision)
  guard target.baseline.tree == self.baseline.tree else {
    raise WorkspaceError(
      "Relocated template differs from the recorded baseline",
    )
  }
  target
}

///|
/// A local ref and the immutable descendant commit it pointed to when listed.
pub struct GitVersion {
  refname : String
  revision : String
}

///|
/// List locally known branch and tag refs pointing to descendants of the
/// recorded commit. Results are sorted by full ref name. No fetching occurs.
pub async fn GitSource::discover(self : GitSource) -> Array[GitVersion] {
  let baseline = self.baseline.revision
  let listing = @utf8.decode(
    git_read(
      self.repository,
      [
        "for-each-ref",
        "--contains=" + baseline,
        "--no-merged=" + baseline,
        "--sort=refname",
        "--format=%(refname)%09%(objecttype)%09%(objectname)%09%(*objecttype)%09%(*objectname)",
        "refs/heads",
        "refs/tags",
        "refs/remotes",
      ],
      1048576,
    ),
    ignore_bom=false,
  )
  let versions = []
  for line in listing.split("\n") {
    if line.is_empty() {
      continue
    }
    guard line.split("\t").to_array()
      is [refname, kind, oid, peeled_kind, peeled_oid] else {
      raise WorkspaceError("Invalid Git version listing")
    }
    let revision = match (kind, peeled_kind) {
      ("commit", _) => oid.to_owned()
      ("tag", "commit") => peeled_oid.to_owned()
      ("tag", "tag") => {
        let object = oid.to_owned()
        require_git_sha(object)
        @utf8.decode(
          git_read(
            self.repository,
            ["rev-parse", "--verify", object + "^{commit}"],
            4096,
          ),
        )
        .trim()
        .to_owned()
      }
      _ => raise WorkspaceError("Expected a commit ref: " + refname.to_owned())
    }
    require_git_sha(revision)
    versions.push({ refname: refname.to_owned(), revision, })
  }
  versions
}

///|
/// Plan an upgrade against a commit from the recorded source.
pub async fn GitSource::plan_upgrade(
  self : GitSource,
  current : @graft.Tree,
  revision : String,
) -> @graft.Plan {
  self.plan_upgrade_with_renames(current, revision, [])
}

///|
/// Plan an upgrade against a pinned Git commit with explicit template moves.
pub async fn GitSource::plan_upgrade_with_renames(
  self : GitSource,
  current : @graft.Tree,
  revision : String,
  renames : Array[@graft.FileRename],
) -> @graft.Plan {
  self.verify_parameterized_baseline()
  let target = self.at(revision)
  @graft.plan_update_with_renames(
    self.baseline,
    current,
    target.baseline,
    renames,
  )
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
  self.verify_parameterized_baseline()
  let next = plan.next_baseline()
  let target = match plan.parameter_migration() {
    Some(migration) => self.capture_migrated(next.revision, migration)
    None => self.at(next.revision)
  }
  guard target.baseline == next else {
    raise WorkspaceError("Plan target differs from the pinned Git template")
  }
  target
}

///|
async fn GitSource::capture_migrated(
  self : GitSource,
  revision : String,
  migration : @graft.ParameterMigration,
) -> GitSource {
  guard self.parameters is Some(parameters) else {
    raise WorkspaceError(
      "Parameter migration requires a parameterized Git source",
    )
  }
  capture_parameterized_git_source(
    self.repository,
    revision,
    self.subdir,
    migration.apply(parameters),
  )
}

///|
/// Rebuild the old template and render the target with a validated recipe transition.
pub async fn GitSource::plan_parameter_upgrade(
  self : GitSource,
  current : @graft.Tree,
  revision : String,
  migration : @graft.ParameterMigration,
  renames~ : Array[@graft.FileRename] = [],
) -> @graft.Plan {
  self.verify_replay()
  let target = self.capture_migrated(revision, migration)
  @graft.plan_parameter_upgrade(
    self.baseline,
    current,
    target.baseline,
    migration,
    renames~,
  )
}
