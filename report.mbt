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
  let fields = [
    Json::string("moongraft.report"),
    Json::string(if self.renames.is_empty() { "1" } else { "2" }),
    Json::string(self.baseline.template_id),
    Json::string(self.baseline.revision),
    Json::string(self.next.revision),
    Json::array(rows),
    Json::array(self.unresolved().map(Json::string)),
  ]
  if !self.renames.is_empty() {
    fields.push(rename_rows(self.renames))
  }
  Json::array(fields).stringify() + "\n"
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
    Conflict(RenameSourceDeleted) => "conflict:project-deleted/template-moved"
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
  if self.parameter_migration is Some(migration) {
    for (from, to) in migration.renames {
      output.write_string("parameter-rename\t" + from + "\t" + to + "\n")
    }
    for (name, _) in migration.defaults {
      output.write_string("parameter-default\t" + name + "\n")
    }
    for name in migration.drops {
      output.write_string("parameter-drop\t" + name + "\n")
    }
  }
  for rename in self.renames {
    output.write_string(
      "move\t" + rename.from_path + "\t" + rename.to_path + "\n",
    )
  }
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
