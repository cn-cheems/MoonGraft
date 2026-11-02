///|
test "output preview describes result not template provenance and includes modes" {
  let base = @graft.Tree::new([
    @graft.File::text("a", "base"),
    @graft.File::text("gone", "x"),
    @graft.File::text("mode", ""),
  ])
  let project = @graft.Tree::new([
    @graft.File::text("a", "ours"),
    @graft.File::text("gone", "x"),
    @graft.File::text("mode", ""),
    @graft.File::text("business", "keep"),
  ])
  let next = @graft.Tree::new([
    @graft.File::text("a", "theirs"),
    @graft.File::text("mode", "", executable=true),
    @graft.File::new("new", b"\x00\xff"),
  ])
  let plan = @graft.plan_update(
    @graft.track("team", "1", base),
    project,
    @graft.track("team", "2", next),
  )
  try plan.output_changes() catch {
    @graft.Unresolved(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("unresolved preview accepted")
  }
  let resolved = plan.resolve([@graft.Decision::new("a", @graft.KeepLocal)])
  assert_eq(resolved.output_changes(), [
    @graft.Removed("gone", 1, false),
    @graft.Modified("mode", 0, 0, false, true, false),
    @graft.Added("new", 2, false),
  ])
  assert_eq(
    resolved.output_json(),
    @graft.Plan::decode(resolved.encode()).output_json(),
  )
  let unchanged = @graft.plan_update(
    @graft.track("team", "1", project),
    project,
    @graft.track("team", "2", project),
  )
  assert_eq(unchanged.output_changes(), [])
}
