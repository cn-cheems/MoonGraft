///|
/// Validate a batch report and reject any project that is not ready.
/// This checks preparation status. Verify candidate bundles and run project
/// tests separately before acceptance.
pub fn check_git_batch_report(text : String) -> Unit raise {
  ignore(ready_git_batch_projects(text))
}

///|
priv struct BatchReportEntry {
  id : String
  revision : String
  status : String
}

///|
fn parse_git_batch_report(text : String) -> Array[BatchReportEntry] raise {
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
    projects.push({ id, revision, status, })
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
      }
      ("error", String(message)) => {
        guard !message.is_empty() else {
          raise WorkspaceError(
            "Expected an error diagnostic for project: " + id,
          )
        }
      }
      _ =>
        raise WorkspaceError(
          "Unknown or malformed batch status for project: " + id,
        )
    }
  }
  projects
}

///|
fn ready_git_batch_projects(text : String) -> Array[(String, String)] raise {
  let projects = parse_git_batch_report(text)
  let blocked = projects
    .filter(project => project.status != "ready")
    .map(project => project.id + " (" + project.status + ")")
  blocked.sort_by((a, b) => a.lexical_compare(b))
  guard blocked.is_empty() else {
    raise WorkspaceError("Batch preparation blocked: " + blocked.join(", "))
  }
  projects.map(project => (project.id, project.revision))
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
  let has_rules = names.contains("policy.json")
  let metadata_count = 1 +
    (if captured { 1 } else { 0 }) +
    (if has_rules { 1 } else { 0 })
  guard names.length() == projects.length() + metadata_count &&
    names.all(name => {
      name == "report.json" ||
      name == "manifest.json" ||
      name == "policy.json" ||
      projects.any(p => p.0 == name)
    }) else {
    raise WorkspaceError("Batch contains missing or unreported entries")
  }
  let entries = if captured {
    let (version, entries) = parse_git_batch(
      @utf8.decode(read_bytes(destination + "/manifest.json"), ignore_bom=false),
    )
    guard entries.length() == projects.length() &&
      entries.all(entry => projects.contains((entry.id, entry.revision))) else {
      raise WorkspaceError(
        "Report revision differs from the batch manifest or project set",
      )
    }
    guard version != "moongraft.git-batch.v3" || has_rules else {
      raise WorkspaceError("Expected captured batch policy metadata")
    }
    entries
  } else {
    []
  }
  let by_id = Map::from_array(entries.map(entry => (entry.id, entry)))
  let common_policy = if has_rules {
    let value = @json.parse(
      @utf8.decode(read_bytes(destination + "/policy.json"), ignore_bom=false),
    )
    match value {
      Array([String("moongraft.batch-policy.v1"), Null]) => None
      Array([String("moongraft.batch-policy.v1"), String(text)]) => Some(text)
      _ => raise WorkspaceError("Invalid captured batch policy")
    }
  } else {
    None
  }
  for (id, revision) in projects {
    try {
      let directory = destination + "/" + id
      require_directory(directory)
      let names = @fs.readdir(directory, include_hidden=true)
      let has_source = names.contains("source.json")
      let has_policy = names.contains("policy.json")
      let entry = by_id.get(id)
      let expects_policy = entry is Some(entry) &&
        (entry.policy_path is Some(_) || entry.inline_policy is Some(_))
      let expected_count = 2 +
        (if has_source { 1 } else { 0 }) +
        (if has_policy { 1 } else { 0 })
      guard (!captured || has_source) &&
        (!has_rules || !expects_policy || has_policy) &&
        names.length() == expected_count &&
        names.contains("plan.json") &&
        names.contains("candidate") else {
        raise WorkspaceError("Expected a plan and a complete candidate")
      }
      let plan = @graft.Plan::decode(read_text(directory + "/plan.json"))
      if entry is Some({ rules: Some(rules), inline_policy, .. }) {
        guard plan.upgrade_rules() ==
          @graft.UpgradeRules::decode(rules.stringify()) &&
          has_policy == (inline_policy is Some(_)) else {
          raise WorkspaceError(
            "Plan rules or policy presence differ from the captured manifest",
          )
        }
      }
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
      if common_policy is Some(text) {
        ignore(plan.prepare(original.tree, text))
      }
      if has_policy {
        let policy = @utf8.decode(
          read_bytes(directory + "/policy.json"),
          ignore_bom=false,
        )
        if entry is Some({ inline_policy: Some(expected), .. }) {
          guard policy == expected else {
            raise WorkspaceError(
              "Project policy differs from the captured manifest",
            )
          }
        }
        ignore(plan.prepare(original.tree, policy))
      }
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
