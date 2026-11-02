# Reusable library example

This code is compiled and executed by `moon test` on each core target.

```mbt check
///|
test "a downstream caller upgrades and keeps its business file" {
  let old = @graft.Tree::new([@graft.File::text("build.txt", "v1\n")])
  let project = @graft.Tree::new([
    @graft.File::text("build.txt", "v1\n"),
    @graft.File::text("src/business.txt", "team logic\n"),
  ])
  let next = @graft.Tree::new([@graft.File::text("build.txt", "v2\n")])
  let baseline = @graft.track("team/service", "v1", old)
  let new_template = @graft.track("team/service", "v2", next)
  let plan = @graft.plan_update(baseline, project, new_template)
  let reopened = @graft.Plan::decode(plan.encode())
  reopened.validate(project)
  let result = reopened.apply(project)
  assert_eq(
    result.tree.get("src/business.txt"),
    project.get("src/business.txt"),
  )
  assert_eq(result.tree.get("build.txt"), next.get("build.txt"))
  assert_eq(result.baseline.tree, next)
}
```
