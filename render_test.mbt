///|
const RenderDescriptor = "moongraft.render.json"

///|
fn render_fixture(
  config : String,
  files : Array[(String, String)],
) -> @graft.Tree raise {
  tree([(RenderDescriptor, config)] + files)
}

///|
test "render parameters sort canonically and replace literal tokens without touching other bytes" {
  let first = @graft.RenderParameters::decode(
    "[\"moongraft.parameters\",\"1\",[[\"project\",\"demo\"],[\"title\",\"团队\"]]]",
  )
  let reversed = @graft.RenderParameters::decode(
    "[\"moongraft.parameters\",\"1\",[[\"title\",\"团队\"],[\"project\",\"demo\"]]]",
  )
  assert_eq(first.encode(), reversed.encode())
  assert_eq(
    @graft.RenderParameters::decode(first.encode()).encode(),
    first.encode(),
  )
  let source = @graft.Tree::new([
    @graft.File::text(
      RenderDescriptor,
      "[\"moongraft.render\",\"1\",[[\"title\",\"project\"],[\"src/@{project}.txt\"]]]",
    ),
    @graft.File::text(
      "src/@{project}.txt",
      "\u{feff}@{title}\r\n@{project}",
      executable=true,
    ),
    @graft.File::new("blob.bin", b"\x00\xff@{project}"),
  ])
  let output = source.render_parameters(first)
  assert_eq(
    output,
    @graft.Tree::new([
      @graft.File::text(
        "src/demo.txt",
        "\u{feff}团队\r\ndemo",
        executable=true,
      ),
      @graft.File::new("blob.bin", b"\x00\xff@{project}"),
    ]),
  )
  assert_eq(source.render_parameters(reversed).encode(), output.encode())
}

///|
test "render refuses missing declarations, occupied paths and malformed selected text" {
  let params = @graft.RenderParameters::decode(
    "[\"moongraft.parameters\",\"1\",[[\"project\",\"demo\"]]]",
  )
  let text_config = "[\"moongraft.render\",\"1\",[[\"project\"],[\"README.md\"]]]"
  for
    rejected in [
      tree([("README.md", "@{project}")]),
      render_fixture("[\"moongraft.render\",\"2\",[[\"project\"],[]]]", [
        ("doc", ""),
      ]),
      render_fixture("[\"moongraft.render\",\"1\",[[\"unknown\"],[]]]", [
        ("doc", ""),
      ]),
      render_fixture(text_config, [("other.md", "")]),
      render_fixture(text_config, [("README.md", "@{unknown}")]),
      render_fixture(text_config, [("README.md", "never closed @{project")]),
      render_fixture(text_config, [("README.md", "\u{0000}")]),
      render_fixture(text_config, [
        ("README.md", "ok"),
        ("@{project}.txt", "new"),
        ("Demo.txt", "old"),
      ]),
      @graft.Tree::new([
        @graft.File::text(RenderDescriptor, text_config),
        @graft.File::new("README.md", b"\xff"),
      ]),
    ] {
    try rejected.render_parameters(params) catch {
      _ => ()
    } noraise {
      _ => fail("Invalid rendering input was accepted")
    }
  }
  let source = render_fixture(text_config, [("README.md", "@{project}")])
  assert_eq(source.render_parameters(params), tree([("README.md", "demo")]))
}

///|
test "render refuses duplicate parameters and output expansion beyond file budget" {
  for
    malformed in [
      "[\"moongraft.parameters\",\"2\",[[\"project\",\"demo\"]]]", "[\"moongraft.parameters\",\"1\",[[\"project\",\"a\"],[\"project\",\"b\"]]]",
      "[\"moongraft.parameters\",\"1\",[[\"project\",\"a\\nb\"]]]",
    ] {
    try @graft.RenderParameters::decode(malformed) catch {
      @graft.InvalidArchive(_) => ()
      error => raise error
    } noraise {
      _ => fail("Invalid parameter archive accepted")
    }
  }
  let params = @graft.RenderParameters::decode(
    "[\"moongraft.parameters\",\"1\",[[\"p\",\"" + "x".repeat(128) + "\"]]]",
  )
  let source = render_fixture(
    "[\"moongraft.render\",\"1\",[[\"p\"],[\"doc\"]]]",
    [("doc", "@{p}".repeat(16385))],
  )
  try source.render_parameters(params) catch {
    @graft.LimitExceeded(_) => ()
    error => raise error
  } noraise {
    _ => fail("Oversized rendering succeeded")
  }
}
