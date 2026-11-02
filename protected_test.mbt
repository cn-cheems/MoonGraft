///|
test "protected paths cover additions deletions modes directories and case" {
  let before = @graft.Tree::new([
    @graft.File::text("src/old", "old"),
    @graft.File::text("mode", ""),
    @graft.File::text("business", "keep"),
  ])
  let after = @graft.Tree::new([
    @graft.File::text("src/new", "new"),
    @graft.File::text("mode", "", executable=true),
    @graft.File::text("business", "keep"),
  ])
  let plan = @graft.plan_update(
    @graft.track("team", "1", before),
    before,
    @graft.track("team", "2", after),
  )
  plan.check_protected(["business", "src2/"])
  for rule in ["SRC/", "src/new", "src/old", "mode"] {
    try plan.check_protected([rule, rule]) catch {
      @graft.PolicyRejected(reasons) => assert_true(reasons.length() > 0)
      _ => fail("wrong error")
    } noraise {
      _ => fail("protected change allowed")
    }
  }
  plan.check_protected_json("[\"moongraft.protected\",\"1\",[\"business\"]]")
  for
    source in [
      "{}", "[\"moongraft.protected\",\"2\",[]]", "[\"moongraft.protected\",\"1\",[0]]",
      "[\"moongraft.protected\",\"1\",[\"../x\"]]",
    ] {
    try plan.check_protected_json(source) catch {
      _ => ()
    } noraise {
      _ => fail("invalid policy accepted")
    }
  }
  assert_eq(plan.apply(before).tree, after)
}

///|
test "directory policy prevents replacement by a file" {
  let before = @graft.Tree::new([@graft.File::text("src/a", "old")])
  let after = @graft.Tree::new([@graft.File::text("src", "replacement")])
  let plan = @graft.plan_update(
    @graft.track("team", "1", before),
    before,
    @graft.track("team", "2", after),
  )
  try plan.check_protected(["src/"]) catch {
    @graft.PolicyRejected(reasons) => assert_eq(reasons.length(), 2)
    _ => fail("wrong error")
  } noraise {
    _ => fail("directory replacement allowed")
  }
}
