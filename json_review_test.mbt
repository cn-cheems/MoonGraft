///|
test "field review preserves automatic edits and keeps only stable decisions at refresh" {
  let path = "service.json"
  let old = baseline(
    "v1",
    tree([(path, "{\"drop\":null,\"http\":{\"timeout\":10}}")]),
  )
  let project = tree([(path, "{\"http\":{\"timeout\":30,\"port\":8080}}")])
  let next = baseline(
    "v2",
    tree([(path, "{\"drop\":true,\"http\":{\"timeout\":20,\"retries\":3}}")]),
  )
  let plan = @graft.plan_json_upgrade(old, project, next, [path])
  let deleted = plan.json_field_conflict(path, "/drop")
  assert_eq(deleted.base, Some("null"))
  assert_eq(deleted.project, None)
  let take_deletion = @graft.JsonFieldDecision::new(
    "/drop",
    @graft.KeepLocalField,
  )
  let custom = @graft.JsonFieldDecision::new(
    "/http/timeout",
    @graft.SetJsonField(" 9007199254740993 "),
  )
  let pending = plan.resolve_json_fields(path, [take_deletion])
  assert_eq(pending.unresolved(), [path])
  assert_eq(pending.unresolved_json_pointers(path), ["/http/timeout"])
  try pending.apply(project) catch {
    @graft.Unresolved(_) => ()
    error => raise error
  } noraise {
    _ => fail("Partial JSON review exported")
  }
  let complete = pending.resolve_json_fields(path, [custom])
  assert_eq(complete.unresolved(), [])
  assert_eq(complete.json_field_decisions(path).length(), 2)
  assert_eq(complete.decisions(), [])
  assert_eq(
    complete.apply(project).tree,
    tree([
      (
        path, "{\"http\":{\"port\":8080,\"retries\":3,\"timeout\":9007199254740993}}\n",
      ),
    ]),
  )
  let encoded = complete.encode()
  assert_eq(
    encoded,
    plan.resolve_json_fields(path, [custom, take_deletion]).encode(),
  )
  assert_eq(encoded, @graft.Plan::decode(encoded).encode())
  let revised = tree([(path, "{\"http\":{\"timeout\":35,\"port\":8081}}")])
  let refreshed = complete.refresh(revised)
  assert_eq(refreshed.retained_json_fields, [(path, "/drop")])
  assert_eq(refreshed.dropped_json_fields, [(path, "/http/timeout")])
  assert_eq(refreshed.plan.unresolved_json_pointers(path), ["/http/timeout"])
  let reviewed = refreshed.plan.resolve_json_fields(path, [
    @graft.JsonFieldDecision::new("/http/timeout", @graft.TakeTemplateField),
  ])
  assert_eq(
    reviewed.apply(revised).tree,
    tree([(path, "{\"http\":{\"port\":8081,\"retries\":3,\"timeout\":20}}\n")]),
  )
}

///|
test "root choices support explicit null and reject malformed values or unknown pointers atomically" {
  let path = "settings.json"
  let old = baseline("v1", tree([(path, "0")]))
  let project = tree([(path, "1")])
  let next = baseline("v2", tree([(path, "2")]))
  let plan = @graft.plan_json_upgrade(old, project, next, [path])
  let choice = @graft.JsonFieldDecision::new("", @graft.SetJsonField("null"))
  for
    fields in [
      [choice, choice],
      [@graft.JsonFieldDecision::new("/missing", @graft.KeepLocalField)],
      [
        @graft.JsonFieldDecision::new(
          "",
          @graft.SetJsonField("{\"x\":0,\"x\":1}"),
        ),
      ],
    ] {
    try plan.resolve_json_fields(path, fields) catch {
      @graft.InvalidTemplate(_) | @graft.InvalidDecision(_, _) => ()
      error => raise error
    } noraise {
      _ => fail("Invalid field review was accepted")
    }
    assert_eq(plan.unresolved_json_pointers(path), [""])
  }
  let resolved = plan.resolve_json_fields(path, [choice])
  assert_eq(resolved.apply(project).tree, tree([(path, "null\n")]))
  let as_whole_file = resolved.resolve([
    @graft.Decision::new(path, @graft.KeepLocal),
  ])
  assert_eq(as_whole_file.apply(project).tree, project)
  assert_eq(as_whole_file.json_field_decisions(path), [])
}
