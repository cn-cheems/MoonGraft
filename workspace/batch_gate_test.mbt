///|
fn report(rows : Array[Json]) -> String {
  Json::object({
    "format": Json::string("moongraft.git-batch-report.v1"),
    "projects": Json::array(rows),
  }).stringify()
}

///|
fn row(id : String, status : String, detail : Json) -> Json {
  Json::object({
    "id": Json::string(id),
    "revision": Json::string("0123456789012345678901234567890123456789"),
    "status": Json::string(status),
    "detail": detail,
  })
}

///|
test "batch gate accepts ready projects and fails closed on malformed status reports" {
  let ready = row("service", "ready", Json::array([]))
  @workspace.check_git_batch_report(report([ready]))
  for
    invalid in [
      "{}",
      report([]),
      report([ready, ready]),
      report([row("service", "skipped", Json::array([]))]),
      report([
        row("service", "ready", Json::array([Json::string("conflict.txt")])),
      ]),
      report([row("service", "conflicts", Json::array([]))]),
      report([row("service", "error", Json::string(""))]),
      report([row("../outside", "ready", Json::array([]))]),
    ] {
    try @workspace.check_git_batch_report(invalid) catch {
      _ => ()
    } noraise {
      _ => fail("Invalid batch report accepted: " + invalid)
    }
  }
  @workspace.check_git_batch_report(report([ready]))
}

///|
test "batch gate lists every blocked project deterministically" {
  let failed = row("z-error", "error", Json::string("Cannot read source"))
  let conflict = row(
    "a-conflict",
    "conflicts",
    Json::array([Json::string("README.md")]),
  )
  try @workspace.check_git_batch_report(report([failed, conflict])) catch {
    @workspace.WorkspaceError(message) =>
      assert_eq(
        message, "Batch preparation blocked: a-conflict (conflicts), z-error (error)",
      )
    error => raise error
  } noraise {
    _ => fail("Blocked batch accepted")
  }
}
