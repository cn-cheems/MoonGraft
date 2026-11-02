///|
test "rollback restores original bytes modes deleted files and baseline" {
  let base = @graft.Tree::new([
    @graft.File::text("a", "base"),
    @graft.File::new("binary", b"\xff", executable=true),
  ])
  let project = @graft.Tree::new([
    @graft.File::text("a", "ours"),
    @graft.File::new("binary", b"\xff", executable=true),
    @graft.File::text("business", "keep"),
  ])
  let next = @graft.Tree::new([
    @graft.File::text("a", "theirs"),
    @graft.File::text("added", "new"),
  ])
  let baseline = @graft.track("team", "1", base)
  let plan = @graft.plan_update(
    baseline,
    project,
    @graft.track("team", "2", next),
  )
  try plan.rollback(project) catch {
    @graft.Unresolved(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("unresolved rollback accepted")
  }
  let resolved = plan.resolve([@graft.Decision::new("a", @graft.TakeTemplate)])
  let applied = resolved.apply(project)
  let restored = @graft.Plan::decode(resolved.encode()).rollback(applied.tree)
  assert_eq(restored.tree, project)
  assert_eq(restored.baseline, baseline)
  let edited = @graft.Tree::new(
    applied.tree.files() + [@graft.File::text("later", "new work")],
  )
  try resolved.rollback(edited) catch {
    @graft.StaleProject => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("post-upgrade work discarded")
  }
}
