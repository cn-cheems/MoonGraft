///|
test "policy enforces exact boundaries binary additions deletions and net growth" {
  let before = @graft.Tree::new([@graft.File::text("gone", "x")])
  let after = @graft.Tree::new([@graft.File::new("asset", b"\x00\xffx")])
  let plan = @graft.plan_update(
    @graft.track("team", "1", before),
    before,
    @graft.track("team", "2", after),
  )
  plan.check_policy(max_removed=1, max_binary_changes=1, max_growth_bytes=2)
  try
    plan.check_policy(max_removed=0, max_binary_changes=0, max_growth_bytes=1)
  catch {
    @graft.PolicyRejected(reasons) => assert_eq(reasons.length(), 3)
    _ => fail("wrong error")
  } noraise {
    _ => fail("policy bypassed")
  }
  try
    plan.check_policy(max_removed=-1, max_binary_changes=1, max_growth_bytes=2)
  catch {
    @graft.InvalidDecision(_, _) => ()
    _ => fail("wrong negative-limit error")
  } noraise {
    _ => fail("negative limit accepted")
  }
  assert_eq(plan.apply(before).tree, after)
}
