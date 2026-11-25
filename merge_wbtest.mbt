///|
test "exhaustive LCS edits reconstruct their target without loss" {
  let texts = [
    b"", b"a", b"a\n", b"b\n", b"a\nb\n", b"b\na\n", b"a\na\n", b"a\r\nb", b"\xef\xbb\xbfa\n",
  ]
  for before in texts {
    for after in texts {
      let base = lines(before)
      let edits = diff_lines(base, lines(after))
      let output : Array[Byte] = []
      let mut cursor = 0
      for edit in edits {
        assert_true(edit.start >= cursor && edit.end >= edit.start)
        for i in cursor..<edit.start {
          for byte in base[i] {
            output.push(byte)
          }
        }
        for line in edit.replacement {
          for byte in line {
            output.push(byte)
          }
        }
        cursor = edit.end
      }
      for i in cursor..<base.length() {
        for byte in base[i] {
          output.push(byte)
        }
      }
      assert_eq(Bytes::from_array(output), after)
    }
  }
}

///|
test "merge convergence insert boundaries identical hunks and bounded work" {
  assert_eq(
    merge_content(b"a\nb\nc\n", b"A\nb\nc\n", b"A\nb\nC\n"),
    Ok(b"A\nb\nC\n"),
  )
  assert_eq(
    merge_content(b"a\nb\n", b"x\na\nb\n", b"y\na\nb\n"),
    Err(BothModified),
  )
  assert_eq(
    merge_content(b"a\nb\n", b"a\nX\nb\n", b"A\nb\n"),
    Err(BothModified),
  )
  let big = b"a\n".repeat(4097)
  assert_eq(merge_content(big, big + b"x", big + b"y"), Err(TextMergeLimit))
}

///|
test "large sparse edits merge across byte-preserving prefix and suffix windows" {
  let beginning = b"\xef\xbb\xbfstart\r\n" + b"repeat\r\n".repeat(700)
  let middle = b"repeat\r\n".repeat(1300)
  let end = b"repeat\r\n".repeat(700) + b"no final newline"
  let base = beginning + b"alpha\r\n" + middle + b"omega\r\n" + end
  let project = beginning + b"ALPHA\r\n" + middle + b"omega\r\n" + end
  let template = beginning + b"alpha\r\n" + middle + b"OMEGA\r\n" + end
  let expected = beginning + b"ALPHA\r\n" + middle + b"OMEGA\r\n" + end
  assert_eq(merge_content(base, project, template), Ok(expected))
  assert_eq(merge_content(base, template, project), Ok(expected))
  assert_eq(
    merge_content(
      base,
      project,
      beginning + b"REMOTE\r\n" + middle + b"omega\r\n" + end,
    ),
    Err(BothModified),
  )
}

///|
test "large insertion and deletion translate positions and dense changes stay bounded" {
  let prefix = b"p\n".repeat(1024)
  let suffix = b"s\n".repeat(1024)
  let base = prefix + b"first\nspacer\nlast\n" + suffix
  let project = prefix + b"insert\nfirst\nspacer\nlast\n" + suffix
  let template = prefix + b"first\nspacer\n" + suffix
  assert_eq(
    merge_content(base, project, template),
    Ok(prefix + b"insert\nfirst\nspacer\n" + suffix),
  )
  assert_eq(
    merge_content(prefix + suffix, b"x\n".repeat(2048), b"y\n".repeat(2048)),
    Err(TextMergeLimit),
  )
}

///|
test "legacy plans replay long-file decisions with the original diff rules" {
  let padding = b"repeat\n".repeat(1024)
  for moved in [false, true] {
    let destination = if moved { "moved.txt" } else { "long.txt" }
    let baseline = track(
      "app",
      "v1",
      Tree::new([File::new("long.txt", b"first\n" + padding + b"last")]),
    )
    let current = Tree::new([
      File::new("long.txt", b"FIRST\n" + padding + b"last"),
    ])
    let next = track(
      "app",
      "v2",
      Tree::new([File::new(destination, b"first\n" + padding + b"LAST")]),
    )
    let moves = if moved {
      [FileRename::new("long.txt", destination)]
    } else {
      []
    }
    let old_plan = plan_update_for_diff(baseline, current, next, moves, false)
    assert_eq(old_plan.conflict_detail(destination).reason, TextMergeLimit)
    let reviewed = old_plan.resolve([Decision::new(destination, KeepLocal)])
    let archive = reviewed.encode()
    let replay = Plan::decode(archive)
    assert_eq(replay.encode(), archive)
    assert_eq(replay.refresh(current).retained, [destination])
    assert_eq(
      replay.apply(current).tree,
      Tree::new([File::new(destination, b"FIRST\n" + padding + b"last")]),
    )
    let updated = plan_update_with_renames(baseline, current, next, moves)
    assert_eq(updated.unresolved(), [])
    assert_eq(
      Plan::decode(updated.encode()).apply(current).tree,
      Tree::new([File::new(destination, b"FIRST\n" + padding + b"LAST")]),
    )
  }
}
