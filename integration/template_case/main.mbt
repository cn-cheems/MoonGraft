///|
async fn command(args : Array[String], cwd : String) -> Unit {
  let result = @shell.Cmd("moon", args, cwd~).output()
  if !result.stdout().is_empty() {
    println(result.stdout().trim_end())
  }
  if !result.stderr().is_empty() {
    println(result.stderr().trim_end())
  }
  result.check()
}

///|
fn decode_hex(source : String) -> Bytes {
  guard source.length() % 2 == 0 else { abort("Odd-length snapshot hex") }
  let bytes = []
  for i = 0; i < source.length(); i = i + 2 {
    let digits = "0123456789abcdef"
    let a = digits.find(source[i:i + 1]).unwrap()
    let b = digits.find(source[i + 1:i + 2]).unwrap()
    bytes.push((a * 16 + b).to_byte())
  }
  Bytes::from_array(bytes)
}

///|
async fn render(revision : String) -> @graft.Tree {
  let json = @json.parse(
    @fs.read_file("integration/upstream/" + revision + ".json").text(),
  )
  guard json is Array([String(actual), Array(records)]) && actual == revision else {
    fail("Snapshot identity mismatch")
  }
  let raw : Map[String, Bytes] = Map([])
  for record in records {
    guard record
      is Array([String(path), String(mode), String(oid), String(data)]) &&
      ["100644", "120000"].contains(mode) else {
      fail("Unsupported snapshot record")
    }
    let bytes = decode_hex(data)
    let hash = @shell.Cmd(
      "git",
      ["hash-object", "--stdin"],
      stdin=Binary(bytes),
    ).output()
    hash.check()
    guard hash.stdout().trim() == oid else {
      fail("Upstream blob integrity mismatch: " + path)
    }
    guard !raw.contains(path) else { fail("Duplicate upstream path") }
    raw[path] = bytes
  }
  let files = []
  for record in records {
    guard record is Array([String(path), String(mode), String(_), String(_)]) else {
      fail("Invalid record")
    }
    let bytes = raw[path]
    if mode == "120000" {
      guard path == "CLAUDE.md" && @utf8.decode(bytes) == "AGENTS.md" else {
        fail("Unknown symbolic link; adaptation refused")
      }
      files.push(@graft.File::new(path, raw["AGENTS.md"]))
    } else {
      files.push(@graft.File::new(path, bytes))
    }
  }
  let tree = @graft.Tree::new(files)
  let baseline = @graft.track("render-stage", revision, tree)
  let scratch = @fs.tmpdir(prefix="moongraft-render-")
  @workspace.export_result(
    @graft.plan_update(baseline, tree, baseline).apply(tree),
    scratch + "/snapshot",
  )
  let project = scratch + "/snapshot/project"
  // Apply the installed toolchain's own migration identically to both versions.
  command(["fmt"], project)
  command(
    ["add", "--no-update", "--upgrade", "moonbitlang/async@0.22.5"],
    project,
  )
  if @utf8.decode(raw["moon.mod.json"]).contains("moonbitlang/quickcheck") {
    command(
      ["add", "--no-update", "--upgrade", "moonbitlang/quickcheck@0.15.1"],
      project,
    )
  }
  let rendered = []
  for file in tree.files() {
    let path = if file.path == "moon.mod.json" { "moon.mod" } else { file.path }
    rendered.push(
      @graft.File::new(path, @fs.read_file(project + "/" + path).binary()),
    )
  }
  @graft.Tree::new(rendered)
}

///|
async fn main {
  @fs.mkdir("_build", recursive=true, allow_exist=true)
  if @fs.exists("_build/template-case.json") {
    @fs.remove("_build/template-case.json")
  }
  let revision = @shell.Cmd("git", ["rev-parse", "HEAD"]).output()
  revision.check()
  let status = @shell.Cmd("git", ["status", "--porcelain"]).output()
  status.check()
  let before = render("4733b6fe1cf6d9ab51b61e2bbe2643d52d8998d4")
  let after = render("580024abc60f961eb0b5b866fb5b301f889ec365")
  let root = @fs.tmpdir(prefix="moongraft-real-template-")
  let baseline = @graft.track(
    "mizchi/moonbit-template:rendered", "4733b6f", before,
  )
  let next = @graft.track(baseline.template_id, "580024a", after)
  let note = "\n## MoonGraft local case modification\n\nBilling totals use integer cents; invoice_total(3, 125) must equal 375.\n"
  let business = [
    @graft.File::text(
      "src/billing.mbt", "///|\npub fn invoice_total(quantity : Int, unit_price : Int) -> Int { quantity * unit_price }\n",
    ),
    @graft.File::text(
      "src/billing_test.mbt", "///|\ntest \"billing stays correct\" { assert_eq(@lib.invoice_total(3, 125), 375) }\n",
    ),
  ]
  let project = @graft.Tree::new(
    before
    .files()
    .map(file => {
      if file.path == "README.md" {
        @graft.File::text(file.path, @utf8.decode(file.content) + note)
      } else {
        file
      }
    }) +
    business,
  )
  let old_plan = @graft.plan_update(baseline, project, baseline)
  @workspace.export_result(old_plan.apply(project), root + "/before")
  command(["test", "--target", "js"], root + "/before/project")
  let upgrade = @graft.plan_update(baseline, project, next)
  println(upgrade.report())
  guard upgrade
    .changes()
    .any(c => c.path == "README.md" && c.kind == @graft.Merged) else {
    fail("Expected a real upstream/local README merge")
  }
  let expected = @graft.Tree::new(
    after
    .files()
    .map(file => {
      if file.path == "README.md" {
        @graft.File::text(file.path, @utf8.decode(file.content) + note)
      } else {
        file
      }
    }) +
    business,
  )
  let applied = @graft.Plan::decode(upgrade.encode()).apply(project)
  guard applied.tree == expected && applied.baseline == next else {
    fail("Full output or next baseline differs from independent expected tree")
  }
  @workspace.export_result(applied, root + "/after")
  @workspace.verify_export(root + "/after")
  command(["test", "--target", "js"], root + "/after/project")
  command(["build", "--target", "js"], root + "/after/project")
  let application = @shell.Cmd(
    "moon",
    ["run", "--target", "js", "src/main"],
    cwd=root + "/after/project",
  ).output()
  application.check()
  guard application.stdout().trim() == "89" else {
    fail("Upgraded upstream application returned unexpected output")
  }
  let restored = upgrade.rollback(applied.tree)
  guard restored.tree == project && restored.baseline == baseline else {
    fail("Rollback lost project or provenance")
  }
  let report = Json::object({
    "moongraft_revision": Json::string(revision.stdout().trim().to_owned()),
    "working_tree_modified": Json::boolean(!status.stdout().trim().is_empty()),
    "status": Json::string("passed"),
    "upstream": Json::string("https://github.com/mizchi/moonbit-template"),
    "old_revision": Json::string("4733b6fe1cf6d9ab51b61e2bbe2643d52d8998d4"),
    "new_revision": Json::string("580024abc60f961eb0b5b866fb5b301f889ec365"),
    "old_files": Json::number(before.files().length().to_double()),
    "new_files": Json::number(after.files().length().to_double()),
    "result_files": Json::number(expected.files().length().to_double()),
    "tested_targets": Json::array([Json::string("js")]),
    "full_output_verified": Json::boolean(true),
    "adaptations": Json::array([
      Json::string("materialize CLAUDE.md symlink"),
      Json::string("moon fmt configuration migration/formatting"),
      Json::string("pin async 0.22.5 and quickcheck 0.15.1 where present"),
    ]),
    "upstream_warnings_allowed": Json::boolean(true),
  })
  @fs.mkdir("_build", recursive=true, allow_exist=true)
  @fs.write_file("_build/template-case.json", report.stringify(indent=2) + "\n")
  println(root)
}
