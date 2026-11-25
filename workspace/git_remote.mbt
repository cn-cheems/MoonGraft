///|
fn advertised_revision(
  listing : String,
  refname : String,
) -> String raise WorkspaceError {
  let mut found = None
  for row in listing.split("\n") {
    if row.is_empty() {
      continue
    }
    guard row.split_once("\t") is Some((oid, name)) else {
      raise WorkspaceError("Invalid Git remote ref listing")
    }
    if name == refname {
      guard found is None else {
        raise WorkspaceError("Duplicate advertised Git ref: " + refname)
      }
      let revision = oid.to_owned()
      require_git_sha(revision)
      found = Some(revision)
    }
  }
  guard found is Some(revision) else {
    raise WorkspaceError("Remote Git ref not found: " + refname)
  }
  revision
}

///|
async fn remote_git(
  repository : String,
  args : Array[String],
  diagnostic : String,
) -> String {
  // Git transport errors can include a configured URL with credentials.
  let output = @shell.Cmd(
    "git",
    ["--no-replace-objects", "-C", repository] + args,
    env={ "GIT_TERMINAL_PROMPT": "0", "GIT_NO_LAZY_FETCH": "1" },
  ).output(timeout_ms=60000, max_output_bytes=65536) catch {
    _ => raise WorkspaceError(diagnostic + " (Git transport did not finish)")
  }
  guard output.exit_code() == 0 else { raise WorkspaceError(diagnostic) }
  @utf8.decode(output.stdout_bytes(), ignore_bom=false)
}

///|
/// Pin a fully qualified remote branch or tag in an existing SHA-1 template
/// repository. The configured remote is consulted once for the ref's object ID.
/// Git fetches that exact object and retains its commit by SHA for offline use.
///
/// Call `pin_git_ref("./templates", "origin", "refs/tags/v2")` and pass the
/// returned `revision` to `GitSource::plan_upgrade` or `plan_json_upgrade`.
pub async fn pin_git_ref(
  repository : String,
  remote : String,
  refname : String,
) -> GitVersion {
  guard refname.has_prefix("refs/heads/") || refname.has_prefix("refs/tags/") else {
    raise WorkspaceError(
      "Use a full remote ref under refs/heads/ or refs/tags/",
    )
  }
  guard !remote.is_empty() && !remote.has_prefix("-") else {
    raise WorkspaceError("Use the name of a configured Git remote")
  }
  let repository = @fs.realpath(repository).replace_all(old="\\", new="/")
  let object_format = @utf8.decode(
    git_read(repository, ["rev-parse", "--show-object-format"], 4096),
  )
  guard object_format.trim() == "sha1" else {
    raise WorkspaceError("Remote pinning requires a SHA-1 Git repository")
  }
  ignore(git_read(repository, ["check-ref-format", refname], 4096)) catch {
    _ => raise WorkspaceError("Invalid remote Git ref name: " + refname)
  }
  ignore(git_read(repository, ["remote", "get-url", "--", remote], 8192)) catch {
    _ => raise WorkspaceError("Use the name of a configured Git remote")
  }
  let advertisement = remote_git(
    repository,
    ["ls-remote", "--refs", "--", remote, refname],
    "Cannot list Git refs from remote " + remote + ". Check remote access",
  )
  let oid = advertised_revision(advertisement, refname)
  ignore(
    remote_git(
      repository,
      [
        "fetch", "--no-tags", "--no-prune", "--no-prune-tags", "--no-recurse-submodules",
        "--no-write-fetch-head", "--no-auto-gc", "--no-write-commit-graph", "--refmap=",
        "--", remote, oid,
      ],
      "Cannot fetch the advertised Git object " +
      oid +
      " for " +
      refname +
      ". Check remote access or pin again if the ref moved",
    ),
  )
  let revision = @utf8.decode(
      git_read(repository, ["rev-parse", "--verify", oid + "^{commit}"], 4096),
    )
    .trim()
    .to_owned() catch {
      _ =>
        raise WorkspaceError(
          "Remote Git ref does not identify a commit: " + refname,
        )
    }
  require_git_sha(revision)
  ignore(
    git_read(
      repository,
      ["update-ref", "--no-deref", "refs/moongraft/pins/" + revision, revision],
      4096,
    ),
  )
  { refname, revision, }
}
