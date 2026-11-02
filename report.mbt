///|
/// Deterministic machine-readable review data, including explicit decisions.
/// Replacement decisions include their bytes; handle reports like plan archives.
pub fn Plan::report_json(self : Plan) -> String {
  let rows = self.changes.map(change => {
    let decision = self.decisions.filter(d => d.path == change.path)
    Json::array([
      Json::string(change.path),
      Json::string(kind_name(change.kind)),
      if decision.is_empty() {
        Json::null()
      } else {
        decision_json(decision[0])
      },
    ])
  })
  Json::array([
    Json::string("moongraft.report"),
    Json::string("1"),
    Json::string(self.baseline.template_id),
    Json::string(self.baseline.revision),
    Json::string(self.next.revision),
    Json::array(rows),
    Json::array(self.unresolved().map(Json::string)),
  ]).stringify() +
  "\n"
}

///|
fn kind_name(kind : ChangeKind) -> String {
  match kind {
    Unchanged => "unchanged"
    KeptLocal => "keep-local"
    TookTemplate => "take-template"
    Merged => "merged-text"
    Conflict(BothAdded) => "conflict:add/add"
    Conflict(BothModified) => "conflict:modify/modify"
    Conflict(TemplateDeleted) => "conflict:template-deleted/project-modified"
    Conflict(ProjectDeleted) => "conflict:project-deleted/template-modified"
    Conflict(TextMergeLimit) => "conflict:text-merge-limit"
  }
}

///|
/// Stable text report; unresolved paths are explicit even after partial review.
pub fn Plan::report(self : Plan) -> String {
  let output = StringBuilder()
  output.write_string("MoonGraft template upgrade\n")
  output.write_string("Template: " + self.baseline.template_id + "\n")
  output.write_string(
    "Revision: " + self.baseline.revision + " -> " + self.next.revision + "\n",
  )
  for change in self.changes {
    output.write_string(kind_name(change.kind) + "\t" + change.path)
    for decision in self.decisions {
      if decision.path == change.path {
        let action = match decision.resolution {
          KeepLocal => "keep-local"
          TakeTemplate => "take-template"
          Replace(_) => "replace"
          Delete => "delete"
        }
        output.write_string("\tresolved:" + action)
      }
    }
    output.write_string("\n")
  }
  output.write_string(
    "Unresolved: " + self.unresolved().length().to_string() + "\n",
  )
  output.to_string()
}
