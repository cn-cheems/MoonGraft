///|
priv struct Edit {
  start : Int32
  end : Int32
  replacement : Array[Bytes]
} derive(Eq)

///|
fn lines(content : Bytes) -> Array[Bytes] {
  let result = []
  let mut start = 0
  for i in 0..<content.length() {
    if content[i] == b'\n' {
      result.push(content[start:i + 1].to_owned())
      start = i + 1
    }
  }
  if start < content.length() {
    result.push(content[start:].to_owned())
  }
  result
}

///|
fn is_text(content : Bytes) -> Bool {
  for byte in content {
    if byte == 0 {
      return false
    }
  }
  ignore(@utf8.decode(content, ignore_bom=false) catch { _ => return false })
  true
}

///|
// LCS produces deterministic non-overlapping edits against one common base.
fn diff_lines(base : Array[Bytes], changed : Array[Bytes]) -> Array[Edit] {
  let width = changed.length() + 1
  let table = Array::make((base.length() + 1) * width, 0)
  for i = base.length() - 1; i >= 0; i = i - 1 {
    for j = changed.length() - 1; j >= 0; j = j - 1 {
      table[i * width + j] = if base[i] == changed[j] {
        1 + table[(i + 1) * width + j + 1]
      } else {
        Int32::max(table[(i + 1) * width + j], table[i * width + j + 1])
      }
    }
  }
  let edits : Array[Edit] = []
  let mut i = 0
  let mut j = 0
  while i < base.length() || j < changed.length() {
    if i < base.length() && j < changed.length() && base[i] == changed[j] {
      i += 1
      j += 1
    } else {
      let start = i
      let replacement = []
      while i < base.length() || j < changed.length() {
        if i < base.length() && j < changed.length() && base[i] == changed[j] {
          break
        }
        if j < changed.length() &&
          (
            i == base.length() ||
            table[i * width + j + 1] > table[(i + 1) * width + j]
          ) {
          replacement.push(changed[j])
          j += 1
        } else {
          i += 1
        }
      }
      edits.push({ start, end: i, replacement, })
    }
  }
  edits
}

///|
fn overlaps(a : Edit, b : Edit) -> Bool {
  if a.start == a.end && b.start == b.end {
    return a.start == b.start
  }
  // Insertions exactly at another edit's boundary are deliberately conservative.
  if a.start == a.end {
    return a.start >= b.start && a.start <= b.end
  }
  if b.start == b.end {
    return b.start >= a.start && b.start <= a.end
  }
  a.start < b.end && b.start < a.end
}

///|
fn merge_content(
  base : Bytes,
  ours : Bytes,
  remote : Bytes,
) -> Result[Bytes, ConflictReason] {
  if ours == remote {
    return Ok(ours)
  }
  if ours == base {
    return Ok(remote)
  }
  if remote == base {
    return Ok(ours)
  }
  guard is_text(base) && is_text(ours) && is_text(remote) else {
    return Err(BothModified)
  }
  for content in [base, ours, remote] {
    let mut count = 1
    for byte in content {
      if byte == b'\n' {
        count += 1
      }
      if count > 4096 {
        return Err(TextMergeLimit)
      }
    }
  }
  let a = lines(base)
  let b = lines(ours)
  let c = lines(remote)
  // Bound line arrays and LCS memory/work before multiplication/allocation.
  guard a.length() <= 4096 &&
    b.length() <= 4096 &&
    c.length() <= 4096 &&
    (a.length() + 1) * (b.length() + 1) <= 262144 &&
    (a.length() + 1) * (c.length() + 1) <= 262144 else {
    return Err(TextMergeLimit)
  }
  let edits = diff_lines(a, b)
  for incoming in diff_lines(a, c) {
    let mut identical = false
    for existing in edits {
      if existing == incoming {
        identical = true
        break
      }
      if overlaps(existing, incoming) {
        return Err(BothModified)
      }
    }
    if !identical {
      edits.push(incoming)
    }
  }
  edits.sort_by((x, y) => x.start.compare(y.start))
  let output : Array[Byte] = []
  let mut cursor = 0
  for edit in edits {
    for i in cursor..<edit.start {
      for byte in a[i] {
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
  for i in cursor..<a.length() {
    for byte in a[i] {
      output.push(byte)
    }
  }
  Ok(Bytes::from_array(output))
}
