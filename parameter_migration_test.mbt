///|
test "parameter recipe migration explicitly renames, adds and drops values" {
  let old = @graft.RenderParameters::decode(
    "[\"moongraft.parameters\",\"1\",[[\"project\",\"blue\"],[\"obsolete\",\"yes\"],[\"title\",\"Team\"]]]",
  )
  let text = "[\"moongraft.parameter-migration\",\"1\",[[[\"project\",\"service\"]],[[\"tier\",\"standard\"]],[\"obsolete\"]]]"
  let migration = @graft.ParameterMigration::decode(text)
  let expected = @graft.RenderParameters::decode(
    "[\"moongraft.parameters\",\"1\",[[\"tier\",\"standard\"],[\"service\",\"blue\"],[\"title\",\"Team\"]]]",
  )
  assert_eq(migration.apply(old), expected)
  assert_eq(
    @graft.ParameterMigration::decode(migration.encode()).apply(old),
    expected,
  )
  for
    invalid in [
      "[[],[],[\"unknown\"]]", "[[],[[\"project\",\"ignored\"]],[]]", "[[[\"project\",\"title\"]],[],[]]",
      "[[[\"project\",\"service\"]],[],[\"project\"]]", "[[[\"project\",\"service\"],[\"project\",\"alias\"]],[],[]]",
      "[[],[],[]]",
    ] {
    let rule = @graft.ParameterMigration::decode(
      "[\"moongraft.parameter-migration\",\"1\"," + invalid + "]",
    )
    try rule.apply(old) catch {
      @graft.InvalidTemplate(_) => ()
      error => raise error
    } noraise {
      _ => fail("Invalid migration accepted")
    }
  }
  assert_eq(migration.apply(old), expected)
}
