///|
/// Restore the exact pre-upgrade project and baseline into a new value. Reject
/// candidates containing any post-upgrade edits rather than discarding work.
pub fn Plan::rollback(
  self : Plan,
  candidate : Tree,
) -> Applied raise GraftError {
  guard candidate == self.materialize() else { raise StaleProject }
  { tree: self.current, baseline: self.baseline, }
}
