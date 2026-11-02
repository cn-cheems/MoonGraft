///|
test "batch review is bound atomic and rejects stale decisions" {
  let base = @graft.Tree::new([@graft.File::text("a", "base")])
  let ours = @graft.Tree::new([@graft.File::text("a", "ours")])
  let next = @graft.Tree::new([@graft.File::text("a", "next")])
  let plan = @graft.plan_update(
    @graft.track("team", "1", base),
    ours,
    @graft.track("team", "2", next),
  )
  assert_eq(plan.resolve_review(plan.review_template()), plan)
  let review = Json::array([
    Json::string("moongraft.review"),
    Json::string("1"),
    Json::array([
      Json::string(plan.encode()),
      @json.parse("[[\"a\",[\"keep-local\"]]]"),
    ]),
  ]).stringify()
  let resolved = plan.resolve_review(review)
  assert_eq(resolved.apply(ours).tree, ours)
  try resolved.resolve_review(review) catch {
    @graft.InvalidArchive(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("stale review accepted")
  }
  let duplicate = review.replace(
    old="[[\"a\",[\"keep-local\"]]]",
    new="[[\"a\",[\"keep-local\"]],[\"a\",[\"delete\"]]]",
  )
  try plan.resolve_review(duplicate) catch {
    @graft.InvalidDecision(_, _) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("duplicate decision accepted")
  }
  assert_eq(plan.unresolved(), ["a"])
}
