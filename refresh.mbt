///|
/// A refreshed plan and a complete account of previous decisions.
pub struct Refreshed {
  plan : Plan
  retained : Array[String]
  dropped : Array[String]
  retained_json_fields : Array[(String, String)]
  dropped_json_fields : Array[(String, String)]
}

///|
/// Replan against a new project snapshot. Preserve a decision only if the path
/// is still a conflict and all three file versions and reason match exactly.
/// Changes outside conflicts may be incorporated, never silently overwritten.
pub fn Plan::refresh(self : Plan, current : Tree) -> Refreshed raise GraftError {
  let updated = plan_update_for_diff(
    self.baseline,
    current,
    self.next,
    self.renames,
    self.window_diff,
    parameter_migration?=self.parameter_migration,
    json_paths=self.json_merge_paths(),
  )
  let retained = []
  let dropped = []
  let retained_json_fields = []
  let dropped_json_fields = []
  let decisions = []
  for decision in self.decisions {
    if decision.resolution is JsonFields(fields) {
      let surviving = []
      for field in fields {
        let key = (decision.path, field.pointer)
        let previous = self.find_json_conflict(decision.path, field.pointer)
        if updated.find_json_conflict(decision.path, field.pointer) == previous {
          retained_json_fields.push(key)
          surviving.push(field)
        } else {
          dropped_json_fields.push(key)
        }
      }
      if !surviving.is_empty() {
        decisions.push({ ..decision, resolution: JsonFields(surviving), })
      }
      continue
    }
    let still_conflicts = updated.conflicts().any(c => c.path == decision.path)
    if still_conflicts &&
      self.conflict_detail(decision.path) ==
      updated.conflict_detail(decision.path) {
      retained.push(decision.path)
      decisions.push(decision)
    } else {
      dropped.push(decision.path)
    }
  }
  {
    plan: updated.resolve_combined(decisions),
    retained,
    dropped,
    retained_json_fields,
    dropped_json_fields,
  }
}
