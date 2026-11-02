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
