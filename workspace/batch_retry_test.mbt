///|
fn retry_manifest(version : String, entries : Array[Array[String]]) -> String {
  Json::array([
    Json::string(version),
    Json::array(entries.map(entry => Json::array(entry.map(Json::string)))),
  ]).stringify()
}

///|
test "retry preserves policy paths and target pins and excludes ready entries" {
  let sha = "0123456789012345678901234567890123456789"
  for version in ["moongraft.git-batch.v1", "moongraft.git-batch.v2"] {
    let a = ["a", "a-source.json", "a-project", sha]
    let z = ["z", "z-source.json", "z-project", sha]
    if version == "moongraft.git-batch.v2" {
      a.push("a-policy.json")
      z.push("z-policy.json")
    }
    let manifest = retry_manifest(version, [z, a])
    let statuses = report([
      row("z", "ready", Json::array([])),
      row("a", "error", Json::string("Missing source")),
    ])
    let expected = retry_manifest(version, [a]) + "\n"
    assert_eq(
      @workspace.retry_git_batch_manifest(manifest, statuses),
      Some(expected),
    )
    assert_eq(
      @workspace.retry_git_batch_manifest(
        expected,
        report([row("a", "ready", Json::array([]))]),
      ),
      None,
    )
    assert_eq(
      @workspace.retry_git_batch_manifest(manifest, statuses),
      Some(expected),
    )
  }
}

///|
test "retry rejects unrelated reports and malformed statuses" {
  let sha = "0123456789012345678901234567890123456789"
  let manifest = retry_manifest("moongraft.git-batch.v1", [
    ["a", "source.json", "project", sha],
  ])
  for
    invalid in [
      report([row("b", "ready", Json::array([]))]),
      report([row("a", "ready", Json::array([]))]).replace_all(
        old=sha,
        new="1111111111111111111111111111111111111111",
      ),
      report([row("a", "unknown", Json::array([]))]),
      report([
        row("a", "ready", Json::array([])),
        row("a", "error", Json::string("failure")),
      ]),
    ] {
    try @workspace.retry_git_batch_manifest(manifest, invalid) catch {
      _ => ()
    } noraise {
      _ => fail("Unrelated or malformed retry report was accepted")
    }
  }
}
