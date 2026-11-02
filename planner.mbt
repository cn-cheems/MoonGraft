///|
fn classify(base : File?, ours : File?, remote : File?) -> (ChangeKind, File?) {
  if ours == remote {
    return (if base == ours { Unchanged } else { TookTemplate }, ours)
  }
  if remote == base {
    return (KeptLocal, ours)
  }
  if ours == base {
    return (TookTemplate, remote)
  }
  match (base, ours, remote) {
    (None, _, _) => (Conflict(BothAdded), None)
    (Some(_), None, Some(_)) => (Conflict(ProjectDeleted), None)
    (Some(_), Some(_), None) => (Conflict(TemplateDeleted), None)
    (Some(b), Some(l), Some(r)) =>
      match merge_content(b.content, l.content, r.content) {
        Ok(content) =>
          (
            Merged,
            Some({
              path: l.path,
              content,
              executable: if l.executable == b.executable {
                r.executable
              } else {
                l.executable
              },
            }),
          )
        Err(why) => (Conflict(why), None)
      }
    _ => (Unchanged, ours)
  }
}

///|
fn all_paths(trees : Array[Tree]) -> Array[String] {
  let paths : Map[String, Bool] = Map([])
  for tree in trees {
    for file in tree.entries {
      paths[file.path] = true
    }
  }
  let result = paths.keys().to_array()
  result.sort_by((a, b) => a.lexical_compare(b))
  result
}

///|
pub fn Plan::conflict_detail(
  self : Plan,
  path : String,
) -> ConflictDetail raise GraftError {
  for change in self.changes {
    if change.path == path && change.kind is Conflict(reason) {
      return {
        reason,
        base: self.baseline.tree.get(path),
        project: self.current.get(path),
        template: self.next.tree.get(path),
      }
    }
  }
  raise InvalidDecision(path, "path is not a conflict in this plan")
}

///|
/// Plan a directory-level upgrade. Rendered inputs must refer to the same
/// template; template execution and revision ordering are the caller's concern.
pub fn plan_update(
  baseline : Baseline,
  current : Tree,
  next : Baseline,
) -> Plan raise GraftError {
  guard baseline.template_id == next.template_id else {
    raise InvalidTemplate(
      "template identifiers differ; an upgrade cannot silently change template ownership",
    )
  }
  let changes = []
  for path in all_paths([baseline.tree, current, next.tree]) {
    let (kind, _) = classify(
      baseline.tree.get(path),
      current.get(path),
      next.tree.get(path),
    )
    changes.push({ path, kind, })
  }
  let plan = { baseline, current, next, changes, decisions: [], }
  // With no content conflicts, validate the combined directory structure now.
  if plan.conflicts().is_empty() {
    ignore(plan.materialize())
  }
  plan
}

///|
/// Return a new plan with the supplied decisions. Partial review is permitted;
/// a failed review never mutates the original plan. Existing decisions can be
/// replaced by one new decision for that path.
pub fn Plan::resolve(
  self : Plan,
  decisions : Array[Decision],
) -> Plan raise GraftError {
  let seen : Map[String, Bool] = Map([])
  let result = self.decisions.copy()
  for decision in decisions {
    guard !seen.contains(decision.path) else {
      raise InvalidDecision(decision.path, "duplicate decision")
    }
    seen[decision.path] = true
    guard self.changes.any(c => c.path == decision.path && c.kind is Conflict(_)) else {
      raise InvalidDecision(
        decision.path,
        "path is not a conflict in this plan",
      )
    }
    if decision.resolution is Replace(file) {
      guard file.path == decision.path else {
        raise InvalidDecision(
          decision.path,
          "replacement must have the same path",
        )
      }
    }
    let mut replaced = false
    for i in 0..<result.length() {
      if result[i].path == decision.path {
        result[i] = decision
        replaced = true
        break
      }
    }
    if !replaced {
      result.push(decision)
    }
  }
  result.sort_by((a, b) => a.path.lexical_compare(b.path))
  let mut replacement_bytes = 0
  for decision in result {
    if decision.resolution is Replace(file) {
      replacement_bytes += file.content.length()
      guard replacement_bytes <= 16777216 else {
        raise LimitExceeded("replacement decisions exceed 16 MiB")
      }
    }
  }
  let plan = { ..self, decisions: result, }
  if plan.unresolved().is_empty() {
    ignore(plan.materialize())
  }
  plan
}

///|
pub fn Plan::unresolved(self : Plan) -> Array[String] {
  self
  .conflicts()
  .filter(c => !self.decisions.any(d => d.path == c.path))
  .map(c => c.path)
}

///|
fn Plan::materialize(self : Plan) -> Tree raise GraftError {
  let unresolved = self.unresolved()
  guard unresolved.is_empty() else { raise Unresolved(unresolved) }
  let files = []
  for change in self.changes {
    let ours = self.current.get(change.path)
    let remote = self.next.tree.get(change.path)
    let (_, automatic) = classify(
      self.baseline.tree.get(change.path),
      ours,
      remote,
    )
    let mut selected = automatic
    if change.kind is Conflict(_) {
      for decision in self.decisions {
        if decision.path == change.path {
          selected = match decision.resolution {
            KeepLocal => ours
            TakeTemplate => remote
            Replace(file) => Some(file)
            Delete => None
          }
          break
        }
      }
    }
    if selected is Some(file) {
      files.push(file)
    }
  }
  Tree::new(files)
}

///|
/// Verify the entire project snapshot, decisions and output structure.
pub fn Plan::validate(self : Plan, current : Tree) -> Unit raise GraftError {
  guard current == self.current else { raise StaleProject }
  ignore(self.materialize())
}

///|
/// Pure atomic application: either returns a complete new tree plus its baseline
/// or raises, leaving both the plan and caller's tree unchanged.
pub fn Plan::apply(self : Plan, current : Tree) -> Applied raise GraftError {
  guard current == self.current else { raise StaleProject }
  { tree: self.materialize(), baseline: self.next, }
}
