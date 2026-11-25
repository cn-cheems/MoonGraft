///|
test "explicit move carries local edits through planning, archives and rollback" {
  let old_path = "ci/build.yml"
  let target_path = ".github/workflows/build.yml"
  let old = baseline("v1", tree([(old_path, "alpha\r\nbeta\r\ngamma")]))
  let current = tree([
    (old_path, "ALPHA\r\nbeta\r\ngamma"),
    ("business.txt", "owned locally"),
  ])
  let next = baseline("v2", tree([(target_path, "alpha\r\nbeta\r\nGAMMA")]))
  let mapping_text =
    #|["moongraft.renames","1",[["ci/build.yml",".github/workflows/build.yml"]]]
  let mappings = @graft.FileRename::decode_list(mapping_text)
  let plan = @graft.plan_update_with_renames(old, current, next, mappings)
  assert_eq(plan.renames(), mappings)
  assert_eq(plan.unresolved(), [])
  assert_true(
    plan.report().contains("move\tci/build.yml\t.github/workflows/build.yml"),
  )
  assert_true(plan.report_json().contains("\"moongraft.report\",\"2\""))
  let decoded = @graft.Plan::decode(plan.encode())
  assert_eq(decoded.encode(), plan.encode())
  let applied = decoded.apply(current)
  assert_eq(
    applied.tree,
    tree([
      (target_path, "ALPHA\r\nbeta\r\nGAMMA"),
      ("business.txt", "owned locally"),
    ]),
  )
  assert_eq(applied.baseline, next)
  let rollback = decoded.rollback(applied.tree)
  assert_eq(rollback.tree, current)
  assert_eq(rollback.baseline, old)
  try decoded.check_protected([old_path]) catch {
    @graft.PolicyRejected(_) => ()
    error => raise error
  } noraise {
    _ => fail("Policy allowed moving a protected file")
  }
  try decoded.apply(tree([(old_path, "unreviewed work")])) catch {
    @graft.StaleProject => ()
    error => raise error
  } noraise {
    _ => fail("Plan accepted a changed source tree")
  }
}

///|
test "move conflicts expose original versions and refresh notices changes to the old path" {
  let old = baseline("v1", tree([("old.txt", "base")]))
  let next = baseline("v2", tree([("new.txt", "upstream")]))
  let current = tree([("old.txt", "local")])
  let mappings = [@graft.FileRename::new("old.txt", "new.txt")]
  let plan = @graft.plan_update_with_renames(old, current, next, mappings)
  let detail = plan.conflict_detail("new.txt")
  assert_eq(detail.base, old.tree.get("old.txt"))
  assert_eq(detail.project, current.get("old.txt"))
  assert_eq(detail.template, next.tree.get("new.txt"))
  assert_eq(plan.unresolved(), ["new.txt"])
  let resolved = plan.resolve([
    @graft.Decision::new("new.txt", @graft.KeepLocal),
  ])
  let decoded = @graft.Plan::decode(resolved.encode())
  assert_eq(decoded.apply(current).tree, tree([("new.txt", "local")]))
  let unrelated = decoded.refresh(
    tree([("old.txt", "local"), ("other.txt", "untouched")]),
  )
  assert_eq(unrelated.retained, ["new.txt"])
  assert_eq(unrelated.plan.renames(), mappings)
  let edited = decoded.refresh(tree([("old.txt", "local changed again")]))
  assert_eq(edited.dropped, ["new.txt"])
  assert_eq(edited.plan.unresolved(), ["new.txt"])
  let deleted = tree([])
  let pure_move = baseline("v2", tree([("new.txt", "base")]))
  let deletion_plan = @graft.plan_update_with_renames(
    old, deleted, pure_move, mappings,
  )
  assert_eq(
    deletion_plan.conflict_detail("new.txt").reason,
    @graft.RenameSourceDeleted,
  )
  let retained_deletion = deletion_plan.resolve([
    @graft.Decision::new("new.txt", @graft.KeepLocal),
  ])
  assert_eq(retained_deletion.apply(deleted).tree, deleted)
  let restored_template = deletion_plan.resolve([
    @graft.Decision::new("new.txt", @graft.TakeTemplate),
  ])
  assert_eq(restored_template.apply(deleted).tree, pure_move.tree)
}

///|
test "move declarations reject invalid or occupied destinations and serialize deterministically" {
  let old = baseline("v1", tree([("a", "alpha"), ("b", "beta")]))
  let next = baseline("v2", tree([("c", "alpha"), ("d", "beta")]))
  let first = @graft.FileRename::new("a", "c")
  let second = @graft.FileRename::new("b", "d")
  for
    invalid in [
      [first, first],
      [first, @graft.FileRename::new("b", "c")],
      [@graft.FileRename::new("a", "a")],
      [@graft.FileRename::new("missing", "c")],
      [@graft.FileRename::new("a", "../c")],
    ] {
    try @graft.plan_update_with_renames(old, old.tree, next, invalid) catch {
      @graft.InvalidTemplate(_) | @graft.InvalidPath(_, _) => ()
      error => raise error
    } noraise {
      _ => fail("Invalid file move was accepted")
    }
  }
  for occupied in ["c", "C", "c/nested"] {
    let current = tree([("a", "alpha"), ("b", "beta"), (occupied, "local")])
    try
      @graft.plan_update_with_renames(old, current, next, [first, second])
    catch {
      @graft.InvalidTemplate(_) | @graft.StructuralCollision(_, _) => ()
      error => raise error
    } noraise {
      _ => fail("Occupied destination was accepted")
    }
  }
  let plan = @graft.plan_update_with_renames(old, old.tree, next, [
    first, second,
  ])
  let reversed = @graft.plan_update_with_renames(old, old.tree, next, [
    second, first,
  ])
  assert_eq(plan.encode(), reversed.encode())
  assert_eq(plan.report_json(), reversed.report_json())
  let legacy = @graft.plan_update(old, old.tree, next)
  assert_eq(@graft.Plan::decode(legacy.encode()).encode(), legacy.encode())
  assert_true(legacy.encode().has_prefix("[\"moongraft.plan\",\"1\","))
  let malformed = plan
    .encode()
    .replace_all(
      old="[[\"a\",\"c\"],[\"b\",\"d\"]]",
      new="[[\"a\",\"c\"],[\"b\",\"c\"]]",
    )
  try @graft.Plan::decode(malformed) catch {
    @graft.InvalidTemplate(_) => ()
    error => raise error
  } noraise {
    _ => fail("Archive decode skipped rename validation")
  }
}

///|
test "case-only binary moves retain bytes and executable mode" {
  let data = b"\x00\xff"
  let old_tree = @graft.Tree::new([
    @graft.File::new("Runner", data, executable=true),
  ])
  let next_tree = @graft.Tree::new([
    @graft.File::new("runner", data, executable=true),
  ])
  let plan = @graft.plan_update_with_renames(
    baseline("v1", old_tree),
    old_tree,
    baseline("v2", next_tree),
    [@graft.FileRename::new("Runner", "runner")],
  )
  assert_eq(plan.apply(old_tree).tree, next_tree)
}
