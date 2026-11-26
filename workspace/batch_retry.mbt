///|
/// Select only conflicted or failed entries from the original manifest.
/// Preserve their target SHAs, paths, policy files and manifest version.
/// Return None when all projects are ready, never an unusable empty manifest.
pub fn retry_git_batch_manifest(
  manifest : String,
  report : String,
) -> String? raise {
  let (version, entries) = parse_git_batch(manifest)
  let statuses = parse_git_batch_report(report)
  guard entries.length() == statuses.length() &&
    entries.all(entry => {
      statuses.any(status => {
        status.id == entry.id && status.revision == entry.revision
      })
    }) else {
    raise WorkspaceError(
      "Retry report does not match the manifest project IDs and target revisions",
    )
  }
  let selected = entries.filter(entry => {
    statuses.any(status => status.id == entry.id && status.status != "ready")
  })
  if selected.is_empty() {
    return None
  }
  let rows = selected.map(entry => entry.row)
  Some(
    Json::array([Json::string(version), Json::array(rows)]).stringify() + "\n",
  )
}
