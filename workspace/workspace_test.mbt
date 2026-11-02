///|
async test "read-only export verification refuses missing and unknown data without repair" {
  let root = fixture()
  defer @fs.rmdir(root, recursive=true)
  let tree = @workspace.scan(root + "/source")
  let base = @graft.track("team", "v1", tree)
  @workspace.export_result(
    @graft.plan_update(base, tree, base).apply(tree),
    root + "/candidate",
  )
  @workspace.verify_export(root + "/candidate")
  @fs.remove(root + "/candidate/project/a.txt")
  try @workspace.verify_export(root + "/candidate") catch {
    _ => ()
  } noraise {
    _ => fail("missing file accepted")
  }
  assert_false(@fs.exists(root + "/candidate/project/a.txt"))
  @workspace.resume_export(root + "/candidate")
  @fs.write_file(root + "/candidate/unexpected.txt", "human data")
  try @workspace.verify_export(root + "/candidate") catch {
    _ => ()
  } noraise {
    _ => fail("unknown data accepted")
  }
  assert_eq(
    @workspace.read_text(root + "/candidate/unexpected.txt"),
    "human data",
  )
}

///|
async test "nested destinations are rejected below multiple directory levels" {
  let root = fixture()
  defer @fs.rmdir(root, recursive=true)
  @fs.mkdir(root + "/source/deep")
  @fs.mkdir(root + "/source/deep/nested")
  try
    @workspace.require_outside(
      root + "/source/deep/nested/export",
      root + "/source",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("deeply nested output accepted")
  }
}

///|
async fn fixture() -> String {
  let root = @fs.tmpdir(prefix="moongraft-test-")
  @fs.mkdir(root + "/source")
  @fs.mkdir(root + "/source/.git")
  @fs.write_file(
    root + "/source/.git/config",
    "explicitly excluded Git metadata",
  )
  @fs.write_file(root + "/source/a.txt", "one\ntwo\nthree\n")
  @fs.write_file(root + "/source/asset.bin", b"\x00\xff")
  root
}

///|
async test "scan export resume and source preservation on real files" {
  let root = fixture()
  defer @fs.rmdir(root, recursive=true)
  let original = @workspace.scan(root + "/source")
  assert_eq(original.files().length(), 2)
  let baseline = @graft.track("service", "v1", original)
  let next = @graft.track(
    "service",
    "v2",
    @graft.Tree::new([
      @graft.File::text("a.txt", "ONE\ntwo\nthree\n"),
      @graft.File::new("asset.bin", b"\x00\xff"),
      @graft.File::text("nested/new.txt", "added\n"),
    ]),
  )
  let plan = @graft.plan_update(baseline, original, next)
  @workspace.require_outside(root + "/candidate", root + "/source")
  @workspace.export_result(plan.apply(original), root + "/candidate")
  assert_eq(@workspace.scan(root + "/candidate/project"), next.tree)
  assert_eq(@workspace.scan(root + "/source"), original)
  @workspace.resume_export(root + "/candidate")
  assert_eq(
    @graft.Baseline::decode(
      @workspace.read_text(root + "/candidate/baseline.json"),
    ),
    next,
  )
  try
    @workspace.export_result(plan.apply(original), root + "/candidate")
  catch {
    _ => ()
  } noraise {
    _ => fail("existing destination overwritten")
  }
}

///|
async test "partial scratch recovery and tampered candidate rejection" {
  let root = fixture()
  defer @fs.rmdir(root, recursive=true)
  let original = @workspace.scan(root + "/source")
  let base = @graft.track("service", "v1", original)
  let applied = @graft.plan_update(base, original, base).apply(original)
  @workspace.export_result(applied, root + "/candidate")
  @fs.remove(root + "/candidate/complete.json")
  @fs.remove(root + "/candidate/project/a.txt")
  @fs.write_file(
    root + "/candidate/pending.json",
    Json::string("a.txt").stringify(),
  )
  @fs.write_file(root + "/candidate/pending.bin", "one\nt")
  @workspace.resume_export(root + "/candidate")
  assert_eq(@workspace.scan(root + "/candidate/project"), original)
  assert_false(@fs.exists(root + "/candidate/pending.bin"))
  @fs.write_file(root + "/candidate/project/a.txt", "manual edit")
  try @workspace.resume_export(root + "/candidate") catch {
    _ => ()
  } noraise {
    _ => fail("tampered candidate accepted")
  }
  assert_eq(
    @workspace.read_text(root + "/candidate/project/a.txt"),
    "manual edit",
  )
  assert_eq(@workspace.scan(root + "/source"), original)
}

///|
async test "unrelated files invalid scratch and unknown intent refused without deletion" {
  let root = fixture()
  defer @fs.rmdir(root, recursive=true)
  let original = @workspace.scan(root + "/source")
  let base = @graft.track("service", "v1", original)
  @workspace.export_result(
    @graft.plan_update(base, original, base).apply(original),
    root + "/candidate",
  )
  @fs.write_file(root + "/candidate/notes.txt", "human data")
  try @workspace.resume_export(root + "/candidate") catch {
    _ => ()
  } noraise {
    _ => fail("unknown root entry accepted")
  }
  assert_eq(@workspace.read_text(root + "/candidate/notes.txt"), "human data")
  @fs.remove(root + "/candidate/notes.txt")
  @fs.remove(root + "/candidate/project/a.txt")
  @fs.write_file(
    root + "/candidate/pending.json",
    Json::string("a.txt").stringify(),
  )
  @fs.write_file(root + "/candidate/pending.bin", "unrelated bytes")
  try @workspace.resume_export(root + "/candidate") catch {
    _ => ()
  } noraise {
    _ => fail("unrelated scratch removed")
  }
  assert_eq(
    @workspace.read_text(root + "/candidate/pending.bin"),
    "unrelated bytes",
  )
}

///|
async test "empty directories limits and nested export destinations fail explicitly" {
  let root = fixture()
  defer @fs.rmdir(root, recursive=true)
  try
    @workspace.require_outside(root + "/source/output", root + "/source")
  catch {
    _ => ()
  } noraise {
    _ => fail("nested export accepted")
  }
  try @workspace.read_bytes(root + "/source/a.txt", limit=2) catch {
    _ => ()
  } noraise {
    _ => fail("byte limit ignored")
  }
  @fs.mkdir(root + "/source/empty")
  try @workspace.scan(root + "/source") catch {
    _ => ()
  } noraise {
    _ => fail("empty directory silently omitted")
  }
}

///|
async test "POSIX symlinks and executable attributes" {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    return
  }
  let root = fixture()
  defer @fs.rmdir(root, recursive=true)
  @fs.chmod(root + "/source/a.txt", 0o755)
  let original = @workspace.scan(root + "/source")
  assert_true(original.get("a.txt").unwrap().executable)
  let base = @graft.track("service", "v1", original)
  @workspace.export_result(
    @graft.plan_update(base, original, base).apply(original),
    root + "/candidate",
  )
  assert_true(@fs.can_execute(root + "/candidate/project/a.txt"))
  @fs.symlink(target="a.txt", root + "/source/link")
  try @workspace.scan(root + "/source") catch {
    _ => ()
  } noraise {
    _ => fail("symlink accepted")
  }
}
