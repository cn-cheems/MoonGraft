///|
/// Validate a batch report and reject any project that is not ready.
/// This checks preparation status. Verify candidate bundles and run project
/// tests separately before acceptance.
pub fn check_git_batch_report(text : String) -> Unit raise {
  ignore(ready_git_batch_projects(text))
}

///|
fn ready_git_batch_projects(text : String) -> Array[(String, String)] raise {
  guard text.length() <= 2097152 else {
    raise WorkspaceError("Batch report exceeds 2 MiB")
  }
  guard @json.parse(text) is Object(report) &&
    report.length() == 2 &&
    report.get("format") is Some(String("moongraft.git-batch-report.v1")) &&
    report.get("projects") is Some(Array(rows)) &&
    !rows.is_empty() &&
    rows.length() <= 16 else {
    raise WorkspaceError(
      "Expected a moongraft.git-batch-report.v1 report with 1–16 projects",
    )
  }
  let ids : Map[String, Bool] = Map([])
  let blocked = []
  let projects = []
  for row in rows {
    guard row is Object(fields) &&
      fields.length() == 4 &&
      fields.get("id") is Some(String(id)) &&
      fields.get("revision") is Some(String(revision)) &&
      fields.get("status") is Some(String(status)) &&
      fields.get("detail") is Some(detail) &&
      !id.is_empty() &&
      id.length() <= 64 &&
      id
      .iter()
      .all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') &&
      !ids.contains(id) else {
      raise WorkspaceError("Invalid or duplicate project in batch report")
    }
    ignore(@graft.File::new(id + "/plan.json", b""))
    ids[id] = true
    projects.push((id, revision))
    match (status, detail) {
      ("ready", Array([])) => require_git_sha(revision)
      ("conflicts", Array(paths)) => {
        require_git_sha(revision)
        guard !paths.is_empty() && paths.length() <= 2048 else {
          raise WorkspaceError("Expected unresolved paths for project: " + id)
        }
        for value in paths {
          guard value is String(path) else {
            raise WorkspaceError("Expected a conflict path for project: " + id)
          }
          ignore(@graft.File::new(path, b""))
        }
        blocked.push(id + " (conflicts)")
      }
      ("error", String(message)) => {
        guard !message.is_empty() else {
          raise WorkspaceError(
            "Expected an error diagnostic for project: " + id,
          )
        }
        blocked.push(id + " (error)")
      }
      _ =>
        raise WorkspaceError(
          "Unknown or malformed batch status for project: " + id,
        )
    }
  }
  blocked.sort_by((a, b) => a.lexical_compare(b))
  guard blocked.is_empty() else {
    raise WorkspaceError("Batch preparation blocked: " + blocked.join(", "))
  }
  projects
}

///|
/// Verify a wholly ready batch read-only, including its plans, revisions,
/// candidate bytes, export metadata and absence of unreported entries.
pub async fn verify_git_batch(destination : String) -> Unit {
  require_directory(destination)
  let text = @utf8.decode(
    read_bytes(destination + "/report.json"),
    ignore_bom=false,
  )
  let projects = ready_git_batch_projects(text)
  let names = @fs.readdir(destination, include_hidden=true)
  let captured = names.contains("manifest.json")
  let metadata_count = if captured { 2 } else { 1 }
  guard names.length() == projects.length() + metadata_count &&
    names.all(name => {
      name == "report.json" ||
      name == "manifest.json" ||
      projects.any(p => p.0 == name)
    }) else {
    raise WorkspaceError("Batch contains missing or unreported entries")
  }
  if captured {
    let entries = parse_git_batch(
      @utf8.decode(read_bytes(destination + "/manifest.json"), ignore_bom=false),
    )
    guard entries.length() == projects.length() &&
      entries.all(entry => projects.contains((entry.id, entry.revision))) else {
      raise WorkspaceError(
        "Report revision differs from the batch manifest or project set",
      )
    }
  }
  for (id, revision) in projects {
    try {
      let directory = destination + "/" + id
      require_directory(directory)
      let names = @fs.readdir(directory, include_hidden=true)
      let has_source = names.contains("source.json")
      let expected_count = if has_source { 3 } else { 2 }
      guard (!captured || has_source) &&
        names.length() == expected_count &&
        names.contains("plan.json") &&
        names.contains("candidate") else {
        raise WorkspaceError("Expected a plan and a complete candidate")
      }
      let plan = @graft.Plan::decode(read_text(directory + "/plan.json"))
      let next = plan.next_baseline()
      guard next.revision == revision else {
        raise WorkspaceError("Report revision differs from the plan")
      }
      let candidate = directory + "/candidate"
      verify_export(candidate)
      guard @graft.Baseline::decode(read_text(candidate + "/baseline.json")) ==
        next else {
        raise WorkspaceError("Candidate baseline differs from the plan")
      }
      let original = plan.rollback(scan(candidate + "/project"))
      if has_source {
        let source = GitSource::decode(read_text(directory + "/source.json"))
        guard original.baseline == source.baseline else {
          raise WorkspaceError("Captured source differs from the plan baseline")
        }
      }
    } catch {
      error =>
        raise WorkspaceError("Batch project " + id + ": " + batch_error(error))
    }
  }
}
