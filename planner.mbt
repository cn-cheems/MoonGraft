///|
fn classify(
  base : File?,
  ours : File?,
  remote : File?,
  window_diff : Bool,
) -> (ChangeKind, File?) {
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
      match
        merge_content(b.content, l.content, r.content, allow_window=window_diff) {
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
      let mut original = path
      for rename in self.renames {
        if rename.to_path == path {
          original = rename.from_path
          break
        }
      }
      return {
        reason,
        base: self.baseline.tree.get(original),
        project: self.current.get(original),
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
  plan_update_with_renames(baseline, current, next, [])
}

///|
/// Align explicitly moved files at their new paths before three-way comparison.
/// The plan keeps the original snapshots for freshness checks and rollback.
pub fn plan_update_with_renames(
  baseline : Baseline,
  current : Tree,
  next : Baseline,
  renames : Array[FileRename],
) -> Plan raise GraftError {
  plan_update_for_diff(baseline, current, next, renames, true)
}

///|
/// Plan a transition between parameter recipes for the same template source.
pub fn plan_parameter_upgrade(
  baseline : Baseline,
  current : Tree,
  next : Baseline,
  migration : ParameterMigration,
  renames~ : Array[FileRename] = [],
  json_paths~ : Array[String] = [],
) -> Plan raise GraftError {
  plan_update_for_diff(
    baseline,
    current,
    next,
    renames,
    true,
    parameter_migration=migration,
    json_paths~,
  )
}

///|
/// Plan an upgrade with strict JSON merging on explicitly selected paths.
/// When a move is declared, select the file by its destination path.
pub fn plan_json_upgrade(
  baseline : Baseline,
  current : Tree,
  next : Baseline,
  json_paths : Array[String],
  renames~ : Array[FileRename] = [],
) -> Plan raise GraftError {
  plan_update_for_diff(baseline, current, next, renames, true, json_paths~)
}

///|
fn plan_update_for_diff(
  baseline : Baseline,
  current : Tree,
  next : Baseline,
  renames : Array[FileRename],
  window_diff : Bool,
  parameter_migration? : ParameterMigration,
  json_paths~ : Array[String] = [],
) -> Plan raise GraftError {
  if parameter_migration is Some(migration) {
    let (repository, subdir, old_values) = render_identity(baseline.template_id)
    let (new_repository, new_subdir, values) = render_identity(next.template_id)
    guard repository == new_repository &&
      subdir == new_subdir &&
      migration.apply(old_values) == values else {
      raise InvalidTemplate(
        "Parameter migration differs from the target recipe or template source",
      )
    }
  } else if baseline.template_id != next.template_id {
    raise InvalidTemplate(
      "template identifiers differ; an upgrade cannot silently change template ownership",
    )
  }
  let (renames, merge_base, merge_current) = align_renames(
    baseline.tree,
    current,
    next.tree,
    renames,
  )
  guard json_paths.length() <= 2048 else {
    raise LimitExceeded("more than 2048 JSON merge paths")
  }
  let json_changes : Map[String, JsonFileMerge] = Map([])
  for path in json_paths {
    validate_path(path)
    guard !json_changes.contains(path) else {
      raise InvalidTemplate("Duplicate JSON merge path: " + path)
    }
    let base_file = merge_base.get(path)
    let project_file = merge_current.get(path)
    let template_file = next.tree.get(path)
    guard base_file is Some(_) ||
      project_file is Some(_) ||
      template_file is Some(_) else {
      raise InvalidTemplate(
        "JSON merge path is absent from all three trees: " + path,
      )
    }
    json_changes[path] = prepare_json_file(
      path, base_file, project_file, template_file, window_diff,
    )
  }
  let changes = []
  for path in all_paths([merge_base, merge_current, next.tree]) {
    let ours = merge_current.get(path)
    let kind = if ours is None && renames.any(rename => rename.to_path == path) {
      Conflict(RenameSourceDeleted)
    } else if json_changes.get(path) is Some(change) {
      change.kind
    } else {
      classify(merge_base.get(path), ours, next.tree.get(path), window_diff).0
    }
    changes.push({ path, kind, })
  }
  let plan = {
    baseline,
    current,
    next,
    renames,
    merge_base,
    merge_current,
    window_diff,
    parameter_migration,
    json_changes,
    changes,
    decisions: [],
  }
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
  self.resolve_combined(
    decisions.map(decision => {
      path: decision.path,
      resolution: WholeFile(decision.resolution),
    }),
  )
}

///|
fn Plan::resolve_combined(
  self : Plan,
  decisions : Array[ReviewDecision],
) -> Plan raise GraftError {
  let seen : Map[String, Bool] = Map([])
  let result = self.decisions.copy()
  for requested in decisions {
    let decision = match requested.resolution {
      JsonFields(fields) =>
        {
          ..requested,
          resolution: self.normalize_json_decisions(requested.path, fields),
        }
      _ => requested
    }
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
    if decision.resolution is WholeFile(Replace(file)) {
      guard file.path == decision.path else {
        raise InvalidDecision(
          decision.path,
          "replacement must have the same path",
        )
      }
      if self.json_changes.contains(decision.path) {
        ignore(parse_merge_json(file.content, "replacement " + decision.path))
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
    match decision.resolution {
      WholeFile(Replace(file)) => replacement_bytes += file.content.length()
      JsonFields(fields) =>
        for field in fields {
          if field.resolution is SetJsonField(value) {
            replacement_bytes += @utf8.encode(value).length()
            guard replacement_bytes <= 16777216 else {
              raise LimitExceeded("replacement decisions exceed 16 MiB")
            }
          }
        }
      _ => ()
    }
    guard replacement_bytes <= 16777216 else {
      raise LimitExceeded("replacement decisions exceed 16 MiB")
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
  .filter(c => {
    match self.decision_at(c.path) {
      None => true
      Some({ resolution: JsonFields(fields), .. }) =>
        fields.length() != self.json_conflicts(c.path).length()
      Some(_) => false
    }
  })
  .map(c => c.path)
}

///|
fn Plan::materialize(self : Plan) -> Tree raise GraftError {
  let unresolved = self.unresolved()
  guard unresolved.is_empty() else { raise Unresolved(unresolved) }
  let files = []
  for change in self.changes {
    let ours = self.merge_current.get(change.path)
    let remote = self.next.tree.get(change.path)
    let automatic = match self.json_changes.get(change.path) {
      Some(json) => json.output
      None =>
        classify(
          self.merge_base.get(change.path),
          ours,
          remote,
          self.window_diff,
        ).1
    }
    let mut selected = automatic
    if change.kind is Conflict(_) {
      for decision in self.decisions {
        if decision.path == change.path {
          selected = match decision.resolution {
            WholeFile(KeepLocal) => ours
            WholeFile(TakeTemplate) => remote
            WholeFile(Replace(file)) => Some(file)
            WholeFile(Delete) => None
            JsonFields(fields) => {
              let merged = prepare_json_file(
                change.path,
                self.merge_base.get(change.path),
                ours,
                remote,
                self.window_diff,
                resolutions=Map::from_array(
                  fields.map(field => (field.pointer, field.resolution)),
                ),
              )
              guard merged.output is Some(file) && merged.conflicts.is_empty() else {
                raise InvalidDecision(
                  change.path,
                  "JSON fields did not produce a complete file",
                )
              }
              Some(file)
            }
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
