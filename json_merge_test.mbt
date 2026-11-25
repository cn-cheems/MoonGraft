///|
test "JSON merge combines independent keys, sorts objects and preserves exact numbers" {
  let base = b"{\"server\":{\"timeout\":10,\"enabled\":true},\"items\":[{\"z\":1,\"a\":2}],\"wide\":9007199254740992}"
  let project = b"{\"wide\":9007199254740993,\"server\":{\"timeout\":30,\"enabled\":true},\"items\":[{\"a\":2,\"z\":1}]}"
  let template = b"{\"server\":{\"enabled\":true,\"timeout\":10,\"retries\":3},\"wide\":9007199254740992,\"items\":[{\"z\":1,\"a\":2}],\"fraction\":1.00e+0}"
  let expected = b"{\"fraction\":1.00e+0,\"items\":[{\"a\":2,\"z\":1}],\"server\":{\"enabled\":true,\"retries\":3,\"timeout\":30},\"wide\":9007199254740993}\n"
  assert_eq(@graft.merge_json(base, project, template), Ok(expected))
  assert_eq(@graft.merge_json(base, template, project), Ok(expected))
}

///|
test "JSON distinguishes deletion from null and reports escaped conflict pointers" {
  let base = b"{\"nested\":{\"a/b~c\":0,\"null\":null},\"list\":[1],\"wide\":9007199254740992}"
  let project = b"{\"nested\":{\"a/b~c\":1},\"list\":[1,2],\"wide\":9007199254740993}"
  let template = b"{\"nested\":{\"a/b~c\":2,\"null\":true},\"list\":[0,1],\"wide\":9007199254740994}"
  assert_eq(
    @graft.merge_json(base, project, template),
    Err(["/list", "/nested/a~1b~0c", "/nested/null", "/wide"]),
  )
  assert_eq(@graft.merge_json(b"0", b"1", b"2"), Err([""]))
  assert_eq(@graft.merge_json(b"0", b"1", b"1.0"), Err([""]))
  assert_eq(
    @graft.merge_json(b"{\"a\":null}", b"{}", b"{\"a\":null,\"b\":false}"),
    Ok(b"{\"b\":false}\n"),
  )
}

///|
test "JSON rejects duplicate decoded keys, malformed bytes and excessive nesting" {
  for
    invalid in [
      b"{\"key\":1,\"\\u006bey\":2}",
      b"{\"a\":1,}",
      b"\"\\ud800\"",
      b"\xff",
      b"[".repeat(65) + b"0" + b"]".repeat(65),
    ] {
    try @graft.merge_json(b"{}", invalid, b"{}") catch {
      @graft.InvalidTemplate(_) => ()
      error => raise error
    } noraise {
      _ => fail("Invalid JSON was merged")
    }
  }
}

///|
test "JSON merge rejects input exceeding the byte limit and can merge again" {
  let oversized = b" ".repeat(2097152) + b"0"
  try @graft.merge_json(b"0", oversized, b"1") catch {
    @graft.LimitExceeded(_) => ()
    error => raise error
  } noraise {
    _ => fail("Oversized JSON was merged")
  }
  assert_eq(@graft.merge_json(b"0", b"0", b"1"), Ok(b"1\n"))
}

///|
test "JSON policy and conflicts survive serialization and refresh and validate manual replacements" {
  let old = baseline("v1", tree([("settings.json", "{\"x\":0}")]))
  let project = tree([("settings.json", "{\"x\":1}")])
  let next = baseline("v2", tree([("settings.json", "{\"x\":2}")]))
  let plan = @graft.plan_json_upgrade(old, project, next, ["settings.json"])
  let decoded = @graft.Plan::decode(plan.encode())
  assert_eq(decoded.encode(), plan.encode())
  assert_eq(decoded.json_merge_paths(), ["settings.json"])
  assert_eq(decoded.json_conflicts("settings.json"), ["/x"])
  assert_eq(decoded.unresolved(), ["settings.json"])
  assert_true(decoded.report().contains("json-conflict\tsettings.json\t\"/x\""))
  assert_true(decoded.report_json().contains("[\"settings.json\",[\"/x\"]]"))
  let invalid = @graft.File::text("settings.json", "{invalid}")
  try
    decoded.resolve([
      @graft.Decision::new("settings.json", @graft.Replace(invalid)),
    ])
  catch {
    @graft.InvalidTemplate(_) => ()
    error => raise error
  } noraise {
    _ => fail("Invalid replacement was accepted")
  }
  let resolved = decoded.resolve([
    @graft.Decision::new("settings.json", @graft.KeepLocal),
  ])
  assert_eq(resolved.apply(project).tree, project)
  let drifted = tree([("settings.json", "{\"copy\":3,\"x\":1}")])
  let refreshed = resolved.refresh(drifted)
  assert_eq(refreshed.plan.json_merge_paths(), ["settings.json"])
  assert_eq(refreshed.dropped, ["settings.json"])
  assert_eq(refreshed.plan.json_conflicts("settings.json"), ["/x"])
}

///|
test "parameter migration and JSON merge replay together in a plan archive" {
  let parameters = @graft.RenderParameters::decode(
    "[\"moongraft.parameters\",\"1\",[[\"project\",\"blue\"]]]",
  )
  let migration = @graft.ParameterMigration::decode(
    "[\"moongraft.parameter-migration\",\"1\",[[[\"project\",\"service\"]],[],[]]]",
  )
  fn identity(values : @graft.RenderParameters) -> String {
    Json::array([
      Json::string("template"),
      Json::string(""),
      Json::string("moongraft.render.v1"),
      Json::string(values.encode()),
    ]).stringify()
  }
  let old = @graft.track(
    identity(parameters),
    "v1",
    tree([("settings.json", "{\"timeout\":10}")]),
  )
  let next = @graft.track(
    identity(migration.apply(parameters)),
    "v2",
    tree([("settings.json", "{\"retries\":3,\"timeout\":10}")]),
  )
  let project = tree([("settings.json", "{\"timeout\":30}")])
  let plan = @graft.plan_parameter_upgrade(old, project, next, migration, json_paths=[
    "settings.json",
  ])
  let decoded = @graft.Plan::decode(plan.encode())
  assert_eq(decoded.encode(), plan.encode())
  assert_eq(decoded.parameter_migration(), Some(migration))
  assert_eq(
    decoded.apply(project).tree,
    tree([("settings.json", "{\"retries\":3,\"timeout\":30}\n")]),
  )
}
