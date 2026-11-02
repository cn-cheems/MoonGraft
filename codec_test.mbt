///|
test "archives preserve all bytes modes metadata and canonical ordering" {
  let bytes = Bytes::makei(256, i => i.to_byte())
  let a = @graft.File::new("z/all-bytes", bytes, executable=true)
  let b = @graft.File::text("a.txt", "中文🙂\r\n\u{feff}")
  let x = @graft.Tree::new([a, b])
  let y = @graft.Tree::new([b, a])
  assert_eq(x.encode(), y.encode())
  assert_eq(@graft.Tree::decode(x.encode()), x)
  let baseline = @graft.track("https://example.org/template", "v1", x)
  assert_eq(@graft.Baseline::decode(baseline.encode()), baseline)
  let external = x.files()
  external.clear()
  assert_eq(x.files().length(), 2)
}

///|
test "malformed unknown version extra field duplicate and unknown payloads rejected" {
  for
    source in [
      "{", "null", "{}", "[]", "[\"moongraft.tree\",\"2\",[]]", "[\"moongraft.tree\",\"1\",[],123]",
      "[\"moongraft.tree\",\"1\",[[\"a\",\"FF\",false]]]", "[\"moongraft.tree\",\"1\",[[\"a\",\"0\",false]]]",
      "[\"moongraft.tree\",\"1\",[[\"a\",\"gg\",false]]]", "[\"moongraft.tree\",\"1\",[[\"a\",\"\",false,0]]]",
      "[\"moongraft.tree\",\"1\",[[\"a\",\"\",0]]]", "[\"moongraft.tree\",\"1\",[[\"a\",\"\",false],[\"a\",\"\",false]]]",
    ] {
    try @graft.Tree::decode(source) catch {
      _ => ()
    } noraise {
      _ => fail("bad archive accepted: " + source)
    }
  }
  assert_eq(
    @graft.Tree::decode("[\"moongraft.tree\",\"1\",[]]").files().length(),
    0,
  )
}

///|
test "portable path and directory invariants" {
  for
    path in [
      "", "/a", "a/", "a//b", ".", "..", "a/../b", "a\\b", "C:/x", "a\u{0000}", "中文",
      "name.", "name ", "CON", "aux.txt", "LPT1.log", ".git/config",
    ] {
    try @graft.File::text(path, "x") catch {
      @graft.InvalidPath(_, _) => ()
      _ => fail("wrong path error")
    } noraise {
      _ => fail("unsafe path accepted: " + path)
    }
  }
  for
    files in [
      [@graft.File::text("a", "x"), @graft.File::text("A", "y")],
      [@graft.File::text("a", "x"), @graft.File::text("a/b", "y")],
      [@graft.File::text("Dir/a", "x"), @graft.File::text("dir/b", "y")],
    ] {
    try @graft.Tree::new(files) catch {
      @graft.StructuralCollision(_, _) => ()
      _ => fail("wrong tree error")
    } noraise {
      _ => fail("collision accepted")
    }
  }
}

///|
test "boundaries fail before silently omitting data" {
  ignore(@graft.File::new("a", Bytes::make(2097152, 0)))
  try @graft.File::new("a", Bytes::make(2097153, 0)) catch {
    @graft.LimitExceeded(_) => ()
    _ => fail("wrong size error")
  } noraise {
    _ => fail("oversized file accepted")
  }
  let maximum = Array::makei(2048, i => {
    @graft.File::text("f" + i.to_string(), "")
  })
  assert_eq(@graft.Tree::new(maximum).files().length(), 2048)
  maximum.push(@graft.File::text("extra", ""))
  try @graft.Tree::new(maximum) catch {
    @graft.LimitExceeded(_) => ()
    _ => fail("wrong count error")
  } noraise {
    _ => fail("too many files accepted")
  }
}

///|
test "partial and complete conflict reviews round trip and unknown actions fail" {
  let base = @graft.Tree::new([
    @graft.File::text("a", "base"),
    @graft.File::text("b", "base"),
  ])
  let project = @graft.Tree::new([
    @graft.File::text("a", "ours"),
    @graft.File::text("b", "ours"),
  ])
  let next = @graft.Tree::new([
    @graft.File::text("a", "theirs"),
    @graft.File::text("b", "theirs"),
  ])
  let plan = @graft.plan_update(
    @graft.track("team", "v1", base),
    project,
    @graft.track("team", "v2", next),
  )
  let partial = plan.resolve([
    @graft.Decision::new(
      "a",
      @graft.Replace(@graft.File::text("a", "coordinated")),
    ),
  ])
  assert_eq(@graft.Plan::decode(partial.encode()), partial)
  assert_eq(@graft.Plan::decode(partial.encode()).unresolved(), ["b"])
  let resolved = partial.resolve([
    @graft.Decision::new("b", @graft.TakeTemplate),
  ])
  assert_eq(
    @graft.Plan::decode(resolved.encode()).apply(project),
    resolved.apply(project),
  )
  let invalid = resolved
    .encode()
    .replace(old="take-template", new="unknown-action")
  try @graft.Plan::decode(invalid) catch {
    @graft.InvalidArchive(_) => ()
    _ => fail("wrong action error")
  } noraise {
    _ => fail("unknown decision accepted")
  }
  assert_eq(plan.conflict_detail("a").base, base.get("a"))
  assert_eq(plan.conflict_detail("a").project, project.get("a"))
  assert_eq(plan.conflict_detail("a").template, next.get("a"))
}
