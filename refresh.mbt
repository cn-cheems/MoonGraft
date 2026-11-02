///|
/// A refreshed plan and a complete account of previous decisions.
pub struct Refreshed {
  plan : Plan
  retained : Array[String]
  dropped : Array[String]
}

///|
/// Replan against a new project snapshot. Preserve a decision only if the path
/// is still a conflict and all three file versions and reason match exactly.
/// Changes outside conflicts may be incorporated, never silently overwritten.
pub fn Plan::refresh(self : Plan, current : Tree) -> Refreshed raise GraftError {
  let updated = plan_update(self.baseline, current, self.next)
  let retained = []
  let dropped = []
  let decisions = []
  for decision in self.decisions {
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
  { plan: updated.resolve(decisions), retained, dropped, }
}
