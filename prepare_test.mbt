///|
test "prepared export enforces policies current snapshot and strict input" {
  let before = @graft.Tree::new([@graft.File::text("gone", "old")])
  let after = @graft.Tree::new([@graft.File::text("new", "new")])
  let plan = @graft.plan_update(
    @graft.track("team", "1", before),
    before,
    @graft.track("team", "2", after),
  )
  let policy = "[\"moongraft.policy\",\"1\",[1,0,0,[]]]"
  assert_eq(plan.prepare(before, policy), plan.apply(before))
  for
    denied in [
      "[\"moongraft.policy\",\"1\",[0,0,0,[]]]", "[\"moongraft.policy\",\"1\",[1,0,0,[\"gone\"]]]",
    ] {
    try plan.prepare(before, denied) catch {
      @graft.PolicyRejected(_) => ()
      _ => fail("wrong error")
    } noraise {
      _ => fail("policy bypassed")
    }
  }
  for
    invalid in [
      "{}", "[\"moongraft.policy\",\"2\",[1,0,0,[]]]", "[\"moongraft.policy\",\"1\",[-1,0,0,[]]]",
      "[\"moongraft.policy\",\"1\",[1.5,0,0,[]]]", "[\"moongraft.policy\",\"1\",[2147483648,0,0,[]]]",
      "[\"moongraft.policy\",\"1\",[1,0,0,[],0]]",
    ] {
    try plan.prepare(before, invalid) catch {
      _ => ()
    } noraise {
      _ => fail("malformed policy accepted")
    }
  }
  try plan.prepare(after, policy) catch {
    @graft.StaleProject => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("stale snapshot accepted")
  }
  assert_eq(plan.prepare(before, policy).tree, after)
}
