///|
test "drift identifies exact paths bytes and modes without changing the plan" {
  let before = @graft.Tree::new([
    @graft.File::text("a", "secret"),
    @graft.File::text("gone", ""),
    @graft.File::text("mode", ""),
  ])
  let base = @graft.track("team", "1", before)
  let plan = @graft.plan_update(base, before, base)
  let after = @graft.Tree::new([
    @graft.File::text("a", "changed"),
    @graft.File::text("mode", "", executable=true),
    @graft.File::text("new", "new"),
  ])
  assert_eq(plan.project_drift(before), [])
  assert_eq(plan.project_drift(after), [
    @graft.Changed("a", true, false),
    @graft.MissingPath("gone"),
    @graft.Changed("mode", false, true),
    @graft.NewPath("new"),
  ])
  assert_false(plan.drift_json(after).contains("secret"))
  assert_eq(
    plan.drift_json(after),
    @graft.Plan::decode(plan.encode()).drift_json(after),
  )
  assert_eq(plan.apply(before).tree, before)
}
