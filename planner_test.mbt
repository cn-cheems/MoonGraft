///|
fn tree(pairs : Array[(String, String)]) -> @graft.Tree raise {
  @graft.Tree::new(pairs.map(p => @graft.File::text(p.0, p.1)))
}

///|
fn baseline(revision : String, files : @graft.Tree) -> @graft.Baseline raise {
  @graft.track("example/service", revision, files)
}

///|
test "upgrade adds changes deletes and preserves project-owned files" {
  let before = tree([("build.txt", "old\n"), ("obsolete.txt", "remove\n")])
  let current = tree([
    ("build.txt", "old\n"),
    ("obsolete.txt", "remove\n"),
    ("business.txt", "ours\n"),
  ])
  let next = tree([("build.txt", "new\n"), ("release.txt", "added\n")])
  let plan = @graft.plan_update(
    baseline("v1", before),
    current,
    baseline("v2", next),
  )
  let applied = plan.apply(current)
  assert_eq(
    applied.tree,
    tree([
      ("build.txt", "new\n"),
      ("release.txt", "added\n"),
      ("business.txt", "ours\n"),
    ]),
  )
  assert_eq(applied.baseline.tree, next)
  assert_eq(applied.baseline.revision, "v2")
}

///|
test "independent line edits merge and preserve CRLF BOM and missing final newline" {
  let before = tree([("a.txt", "\u{feff}alpha\r\nbeta\r\ngamma")])
  let current = tree([("a.txt", "\u{feff}ALPHA\r\nbeta\r\ngamma")])
  let next = tree([("a.txt", "\u{feff}alpha\r\nbeta\r\nGAMMA")])
  let plan = @graft.plan_update(
    baseline("v1", before),
    current,
    baseline("v2", next),
  )
  assert_eq(plan.changes()[0].kind, @graft.Merged)
  assert_eq(
    plan.apply(current).tree,
    tree([("a.txt", "\u{feff}ALPHA\r\nbeta\r\nGAMMA")]),
  )
}

///|
test "all conflict classes need explicit decisions and next upgrade retains customization" {
  let before = tree([
    ("modify.txt", "base"),
    ("removed.txt", "base"),
    ("locally-deleted.txt", "base"),
  ])
  let current = tree([
    ("modify.txt", "ours"),
    ("removed.txt", "ours"),
    ("new.txt", "ours"),
  ])
  let next = tree([
    ("modify.txt", "theirs"),
    ("locally-deleted.txt", "theirs"),
    ("new.txt", "theirs"),
  ])
  let plan = @graft.plan_update(
    baseline("v1", before),
    current,
    baseline("v2", next),
  )
  assert_eq(plan.conflicts().length(), 4)
  try plan.apply(current) catch {
    @graft.Unresolved(paths) => assert_eq(paths.length(), 4)
    _ => fail("expected unresolved conflicts")
  } noraise {
    _ => fail("conflicting plan was applied")
  }
  let resolved = plan.resolve([
    @graft.Decision::new(
      "modify.txt",
      @graft.Replace(@graft.File::text("modify.txt", "combined")),
    ),
    @graft.Decision::new("removed.txt", @graft.KeepLocal),
    @graft.Decision::new("locally-deleted.txt", @graft.TakeTemplate),
    @graft.Decision::new("new.txt", @graft.Delete),
  ])
  let result = resolved.apply(current)
  assert_eq(
    result.tree,
    tree([
      ("modify.txt", "combined"),
      ("removed.txt", "ours"),
      ("locally-deleted.txt", "theirs"),
    ]),
  )
  let again = @graft.plan_update(
    result.baseline,
    result.tree,
    baseline("v3", next),
  )
  assert_eq(again.apply(result.tree).tree, result.tree)
  assert_eq(plan.unresolved().length(), 4)
}

///|
test "invalid decisions are atomic and stale project rejected even for resolved plans" {
  let before = tree([("a", "base")])
  let current = tree([("a", "ours")])
  let plan = @graft.plan_update(
    baseline("v1", before),
    current,
    baseline("v2", tree([("a", "theirs")])),
  )
  for
    decisions in [
      [@graft.Decision::new("missing", @graft.Delete)],
      [
        @graft.Decision::new("a", @graft.Delete),
        @graft.Decision::new("a", @graft.KeepLocal),
      ],
      [
        @graft.Decision::new(
          "a",
          @graft.Replace(@graft.File::text("other", "x")),
        ),
      ],
    ] {
    try plan.resolve(decisions) catch {
      @graft.InvalidDecision(_, _) => ()
      _ => fail("wrong error")
    } noraise {
      _ => fail("invalid review accepted")
    }
    assert_eq(plan.unresolved(), ["a"])
  }
  let resolved = plan.resolve([@graft.Decision::new("a", @graft.KeepLocal)])
  try resolved.apply(tree([("a", "edited after review")])) catch {
    @graft.StaleProject => ()
    _ => fail("wrong stale error")
  } noraise {
    _ => fail("stale plan applied")
  }
  assert_eq(resolved.apply(current).tree, current)
}

///|
test "binary and malformed UTF8 never undergo lossy merging" {
  for bytes in [b"\x00\xff", b"\xc0\xaf", b"\xed\xa0\x80"] {
    let before = @graft.Tree::new([@graft.File::new("asset", bytes)])
    let current = @graft.Tree::new([@graft.File::new("asset", bytes + b"a")])
    let next = @graft.Tree::new([@graft.File::new("asset", bytes + b"b")])
    let plan = @graft.plan_update(
      baseline("v1", before),
      current,
      baseline("v2", next),
    )
    assert_eq(plan.conflicts()[0].kind, @graft.Conflict(@graft.BothModified))
    let resolved = plan.resolve([
      @graft.Decision::new("asset", @graft.TakeTemplate),
    ])
    assert_eq(resolved.apply(current).tree, next)
    assert_eq(@graft.Tree::decode(next.encode()), next)
  }
}

///|
test "execution mode and content changes combine independently" {
  let before = @graft.Tree::new([@graft.File::text("script.sh", "old\n")])
  let current = @graft.Tree::new([
    @graft.File::text("script.sh", "old\n", executable=true),
  ])
  let next = @graft.Tree::new([@graft.File::text("script.sh", "new\n")])
  let plan = @graft.plan_update(
    baseline("v1", before),
    current,
    baseline("v2", next),
  )
  assert_eq(
    plan.apply(current).tree,
    @graft.Tree::new([@graft.File::text("script.sh", "new\n", executable=true)]),
  )
}

///|
test "cross-input file directory and case collisions refuse unsafe output" {
  let empty = tree([])
  let current = tree([("config", "local file")])
  for
    next in [
      tree([("config/settings", "upstream child")]),
      tree([("CONFIG", "upstream")]),
    ] {
    try
      @graft.plan_update(baseline("v1", empty), current, baseline("v2", next))
    catch {
      @graft.StructuralCollision(_, _) => ()
      _ => fail("wrong collision error")
    } noraise {
      _ => fail("structural collision accepted")
    }
  }
}

///|
test "exhaustive small trees satisfy identity convergence and deterministic encoding" {
  let variants = [
    tree([]),
    tree([("a", "")]),
    tree([("a", "x")]),
    tree([("b", "y")]),
    tree([("a", "x"), ("b", "z")]),
  ]
  for base in variants {
    for ours in variants {
      let unchanged = @graft.plan_update(
        baseline("v1", base),
        ours,
        baseline("v2", base),
      )
      assert_eq(unchanged.apply(ours).tree, ours)
      let follow = @graft.plan_update(
        baseline("v1", base),
        base,
        baseline("v2", ours),
      )
      assert_eq(follow.apply(base).tree, ours)
      let converge = @graft.plan_update(
        baseline("v1", base),
        ours,
        baseline("v2", ours),
      )
      assert_eq(converge.apply(ours).tree, ours)
      assert_eq(
        @graft.Plan::decode(unchanged.encode()).encode(),
        unchanged.encode(),
      )
    }
  }
}
