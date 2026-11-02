///|
fn main raise {
  let base = @graft.Tree::new([@graft.File::text("ci.txt", "old\n")])
  let project = @graft.Tree::new([
    @graft.File::text("ci.txt", "old\n"),
    @graft.File::text("src/business.txt", "owned by application\n"),
  ])
  let next = @graft.Tree::new([@graft.File::text("ci.txt", "new\n")])
  let plan = @graft.plan_update(
    @graft.track("team/service", "1", base),
    project,
    @graft.track("team/service", "2", next),
  )
  let restored_plan = @graft.Plan::decode(plan.encode())
  let result = restored_plan.prepare(
    project, "[\"moongraft.policy\",\"1\",[0,0,0,[\"src/\"]]]",
  )
  guard result.tree.get("src/business.txt") == project.get("src/business.txt") &&
    result.tree.get("ci.txt") == next.get("ci.txt") else {
    fail("consumer upgrade lost data")
  }
  guard restored_plan.rollback(result.tree).tree == project else {
    fail("consumer rollback differs")
  }
  guard restored_plan.refresh(project).plan.encode() == restored_plan.encode() else {
    fail("consumer refresh differs")
  }
  println("MoonGraft archive consumer passed")
}
