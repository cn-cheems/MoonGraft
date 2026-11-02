///|
test "refresh retains exact conflict decisions and drops changed ones" {
  let base = @graft.Tree::new([
    @graft.File::text("a", "base"),
    @graft.File::text("b", "base"),
  ])
  let ours = @graft.Tree::new([
    @graft.File::text("a", "ours"),
    @graft.File::text("b", "ours"),
  ])
  let next = @graft.Tree::new([
    @graft.File::text("a", "next"),
    @graft.File::text("b", "next"),
  ])
  let original = @graft.plan_update(
    @graft.track("team", "1", base),
    ours,
    @graft.track("team", "2", next),
  )
  let reviewed = original.resolve([
    @graft.Decision::new("a", @graft.TakeTemplate),
    @graft.Decision::new("b", @graft.KeepLocal),
  ])
  let current = @graft.Tree::new([
    @graft.File::text("a", "ours"),
    @graft.File::text("b", "new work"),
    @graft.File::text("business", "keep"),
  ])
  let refreshed = reviewed.refresh(current)
  assert_eq(refreshed.retained, ["a"])
  assert_eq(refreshed.dropped, ["b"])
  assert_eq(refreshed.plan.unresolved(), ["b"])
  let resolved = refreshed.plan.resolve([
    @graft.Decision::new("b", @graft.KeepLocal),
  ])
  assert_eq(
    resolved.apply(current).tree.get("business"),
    current.get("business"),
  )
  assert_eq(resolved.apply(current).tree.get("b"), current.get("b"))
  assert_eq(reviewed.refresh(ours).plan, reviewed)
  assert_eq(@graft.Plan::decode(refreshed.plan.encode()), refreshed.plan)
  assert_eq(original.decisions(), [])
  try refreshed.plan.resolve_review(reviewed.review_template()) catch {
    @graft.InvalidArchive(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("old review accepted by refreshed plan")
  }
}

///|
test "mode change invalidates decisions and convergence removes obsolete decisions" {
  let base = @graft.Tree::new([@graft.File::text("a", "base")])
  let ours = @graft.Tree::new([@graft.File::text("a", "ours")])
  let next = @graft.Tree::new([@graft.File::text("a", "next")])
  let plan = @graft.plan_update(
    @graft.track("team", "1", base),
    ours,
    @graft.track("team", "2", next),
  ).resolve([@graft.Decision::new("a", @graft.KeepLocal)])
  let mode_changed = @graft.Tree::new([
    @graft.File::text("a", "ours", executable=true),
  ])
  assert_eq(plan.refresh(mode_changed).dropped, ["a"])
  let converged = plan.refresh(next)
  assert_eq(converged.dropped, ["a"])
  assert_eq(converged.plan.unresolved(), [])
  assert_eq(converged.plan.apply(next).tree, next)
}
