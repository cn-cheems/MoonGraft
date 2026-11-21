///|
/// Validate a batch report and reject any project that is not ready.
/// This checks preparation status. Verify candidate bundles and run project
/// tests separately before acceptance.
pub fn check_git_batch_report(text : String) -> Unit raise {
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
}
