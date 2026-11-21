///|
priv struct BatchEntry {
  id : String
  source_path : String
  project : String
  revision : String
  policy_path : String?
}

///|
fn parse_git_batch(manifest : String) -> Array[BatchEntry] raise {
  guard @json.parse(manifest) is Array([String(version), Array(rows)]) &&
    (version == "moongraft.git-batch.v1" || version == "moongraft.git-batch.v2") &&
    !rows.is_empty() &&
    rows.length() <= 16 else {
    raise WorkspaceError(
      "Expected a moongraft.git-batch.v1 or v2 manifest with 1–16 entries",
    )
  }
  let ids : Map[String, Bool] = Map([])
  let entries = []
  for row in rows {
    let (id, source_path, project, revision, policy_path) = match
      (version, row) {
      (
        "moongraft.git-batch.v1",
        Array([String(id), String(source), String(project), String(revision)]),
      ) => (id, source, project, revision, None)
      (
        "moongraft.git-batch.v2",
        Array(
          [
            String(id),
            String(source),
            String(project),
            String(revision),
            String(policy_path),
          ]
        ),
      ) => {
        guard !policy_path.is_empty() else {
          raise WorkspaceError(
            "Version 2 requires a policy file for every project",
          )
        }
        (id, source, project, revision, Some(policy_path))
      }
      _ => raise WorkspaceError("Batch row does not match its manifest version")
    }
    guard !id.is_empty() &&
      id.length() <= 64 &&
      id
      .iter()
      .all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') &&
      !source_path.is_empty() &&
      !project.is_empty() else {
      raise WorkspaceError(
        "Expected [project-id, source-record, project-dir, target-sha] with a lowercase portable ID",
      )
    }
    guard !ids.contains(id) else {
      raise WorkspaceError("Duplicate project ID: " + id)
    }
    ignore(@graft.File::new(id + "/plan.json", b""))
    ids[id] = true
    entries.push({ id, source_path, project, revision, policy_path, })
  }
  entries.sort_by((a, b) => a.id.lexical_compare(b.id))
  entries
}

///|
fn batch_error(error : Error) -> String {
  match error {
    @graft.GraftError::_ as e => e.message()
    WorkspaceError(message) => message
    e => e.to_string()
  }
}

///|
fn make_batch_report(
  entry : BatchEntry,
  status : String,
  detail : Json,
) -> Json {
  Json::object({
    "id": Json::string(entry.id),
    "revision": Json::string(entry.revision),
    "status": Json::string(status),
    "detail": detail,
  })
}

///|
async fn stage_git_entry(
  entry : BatchEntry,
  source : GitSource,
  destination : String,
  policy : String?,
) -> Json {
  let current = scan(entry.project)
  let plan = source.plan_upgrade(current, entry.revision)
  let directory = destination + "/" + entry.id
  @fs.mkdir(directory)
  write_new(directory + "/source.json", source.encode())
  write_new(directory + "/plan.json", plan.encode())
  let conflicts = plan.unresolved()
  if !conflicts.is_empty() {
    return make_batch_report(
      entry,
      "conflicts",
      Json::array(conflicts.map(Json::string)),
    )
  }
  let latest = scan(entry.project)
  let applied = match policy {
    Some(text) => plan.prepare(latest, text)
    None => plan.apply(latest)
  }
  if entry.policy_path is Some(path) {
    let text = @utf8.decode(read_bytes(path), ignore_bom=false)
    write_new(directory + "/policy.json", text)
    ignore(plan.prepare(latest, text))
  }
  export_result(applied, directory + "/candidate")
  make_batch_report(entry, "ready", Json::array([]))
}

///|
/// Stage independent upgrade plans and candidates for a versioned manifest.
/// Each entry keeps its own baseline and explicit target revision. The output
/// directory must be new. Project failures are recorded in the JSON report.
pub async fn stage_git_batch(
  manifest : String,
  destination : String,
  policy? : String,
) -> Json {
  let entries = parse_git_batch(manifest)
  // Check output placement before creating anything, including for bad entries
  // whose source records cannot be decoded.
  for entry in entries {
    if @fs.exists(entry.project) {
      require_outside(destination, entry.project)
    }
    let source = Some(GitSource::decode(read_text(entry.source_path))) catch {
      _ => None
    }
    if source is Some(record) && @fs.exists(record.repository) {
      require_outside(destination, record.repository)
    }
  }
  @fs.mkdir(destination)
  write_new(destination + "/manifest.json", manifest)
  write_new(
    destination + "/policy.json",
    Json::array([
      Json::string("moongraft.batch-policy.v1"),
      match policy {
        Some(text) => Json::string(text)
        None => Json::null()
      },
    ]).stringify(),
  )
  let results = []
  for entry in entries {
    let result = try {
      let source = GitSource::decode(read_text(entry.source_path))
      // Recheck after creating the root so a missing project cannot refer to
      // that newly created directory.
      require_outside(destination, entry.project)
      require_outside(destination, source.repository)
      stage_git_entry(entry, source, destination, policy)
    } catch {
      error =>
        make_batch_report(entry, "error", Json::string(batch_error(error)))
    }
    results.push(result)
  }
  let report = Json::object({
    "format": Json::string("moongraft.git-batch-report.v1"),
    "projects": Json::array(results),
  })
  write_new(destination + "/report.json", report.stringify() + "\n")
  report
}
