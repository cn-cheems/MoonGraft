///|
test "JSON report is deterministic and reflects partial review" {
  let base = @graft.Tree::new([@graft.File::text("a", "base")])
  let ours = @graft.Tree::new([@graft.File::text("a", "ours")])
  let next = @graft.Tree::new([@graft.File::text("a", "next")])
  let plan = @graft.plan_update(
    @graft.track("team", "1", base),
    ours,
    @graft.track("team", "2", next),
  )
  assert_eq(
    plan.report_json(),
    @graft.Plan::decode(plan.encode()).report_json(),
  )
  assert_eq(
    @json.parse(plan.report_json()),
    @json.parse(
      "[\"moongraft.report\",\"1\",\"team\",\"1\",\"2\",[[\"a\",\"conflict:modify/modify\",null]],[\"a\"]]",
    ),
  )
  let resolved = plan.resolve([@graft.Decision::new("a", @graft.KeepLocal)])
  assert_eq(
    @json.parse(resolved.report_json()),
    @json.parse(
      "[\"moongraft.report\",\"1\",\"team\",\"1\",\"2\",[[\"a\",\"conflict:modify/modify\",[\"a\",[\"keep-local\"]]]],[]]",
    ),
  )
}
