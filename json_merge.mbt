///|
fn parse_merge_json(data : Bytes, label : String) -> Json raise GraftError {
  guard data.length() <= 2097152 else {
    raise LimitExceeded("JSON input exceeds 2 MiB: " + label)
  }
  let content = @utf8.decode(data, ignore_bom=false) catch {
    _ => raise InvalidTemplate("JSON input must be UTF-8: " + label)
  }
  @json.parse(
    content,
    max_nesting_depth=64,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    error =>
      raise InvalidTemplate(
        "Invalid JSON in " + label + ": " + error.to_string(),
      )
  }
}

///|
// Json's standard equality compares only the Double part of a number.
// Comparing its preserved spelling distinguishes integers beyond 2^53.
fn json_value_equal(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Number(_, repr=ar), Number(_, repr=br)) => ar == br
    (Array(aa), Array(ba)) => {
      if aa.length() != ba.length() {
        return false
      }
      for i, value in aa {
        if !json_value_equal(value, ba[i]) {
          return false
        }
      }
      true
    }
    (Object(ao), Object(bo)) => {
      if ao.length() != bo.length() {
        return false
      }
      for key, value in ao {
        guard bo.get(key) is Some(other) && json_value_equal(value, other) else {
          return false
        }
      }
      true
    }
    _ => a == b
  }
}

///|
fn json_member_equal(a : Json?, b : Json?) -> Bool {
  match (a, b) {
    (Some(a), Some(b)) => json_value_equal(a, b)
    (None, None) => true
    _ => false
  }
}

///|
fn json_object_keys(objects : Array[Map[String, Json]]) -> Array[String] {
  let keys : Map[String, Bool] = Map([])
  for obj in objects {
    for key, _ in obj {
      keys[key] = true
    }
  }
  let names = keys.keys().to_array()
  names.sort_by((a, b) => a.lexical_compare(b))
  names
}

///|
fn merge_json_member(
  base : Json?,
  project : Json?,
  template : Json?,
  pointer : String,
  conflicts : Array[JsonFieldConflict],
  resolutions : Map[String, JsonFieldResolution],
) -> Json? raise GraftError {
  if json_member_equal(project, template) || json_member_equal(base, template) {
    return project
  }
  if json_member_equal(base, project) {
    return template
  }
  if (base, project, template)
    is (Some(Object(bo)), Some(Object(po)), Some(Object(to))) {
    let result : Map[String, Json] = Map([])
    for key in json_object_keys([bo, po, to]) {
      let segment = key
        .replace_all(old="~", new="~0")
        .replace_all(old="/", new="~1")
      if merge_json_member(
          bo.get(key),
          po.get(key),
          to.get(key),
          pointer + "/" + segment,
          conflicts,
          resolutions,
        )
        is Some(value) {
        result[key] = value
      }
    }
    return Some(Json::object(result))
  }
  match resolutions.get(pointer) {
    Some(KeepLocalField) => return project
    Some(TakeTemplateField) => return template
    Some(SetJsonField(value)) =>
      return Some(parse_merge_json(@utf8.encode(value), "reviewed JSON value"))
    None => ()
  }
  guard conflicts.length() < 256 else {
    raise LimitExceeded("JSON merge exceeds 256 conflicts")
  }
  conflicts.push({
    pointer,
    base: base.map(value => canonical_merge_json(value).stringify()),
    project: project.map(value => canonical_merge_json(value).stringify()),
    template: template.map(value => canonical_merge_json(value).stringify()),
  })
  None
}

///|
fn canonical_merge_json(json : Json) -> Json {
  match json {
    Object(members) => {
      let sorted : Map[String, Json] = Map([])
      for key in json_object_keys([members]) {
        sorted[key] = canonical_merge_json(members[key])
      }
      Json::object(sorted)
    }
    Array(items) => Json::array(items.map(canonical_merge_json))
    _ => json
  }
}

///|
fn merge_parsed_json(
  base : Json,
  project : Json,
  template : Json,
  resolutions~ : Map[String, JsonFieldResolution] = Map([]),
) -> Result[Bytes, Array[JsonFieldConflict]] raise GraftError {
  let conflicts = []
  let merged = merge_json_member(
    Some(base),
    Some(project),
    Some(template),
    "",
    conflicts,
    resolutions,
  )
  if !conflicts.is_empty() {
    return Err(conflicts)
  }
  let bytes = @utf8.encode(
    canonical_merge_json(merged.unwrap()).stringify() + "\n",
  )
  guard bytes.length() <= 2097152 else {
    raise LimitExceeded("merged JSON exceeds 2 MiB")
  }
  if !resolutions.is_empty() {
    // A valid replacement can exceed the depth limit at its destination.
    ignore(parse_merge_json(bytes, "reviewed JSON output"))
  }
  Ok(bytes)
}

///|
/// Merge strict UTF-8 JSON by object key. Arrays are atomic. Numbers compare
/// by their preserved spelling. Conflicts return RFC 6901 pointers ("", the
/// root). Malformed input and exceeded limits raise.
pub fn merge_json(
  base : Bytes,
  project : Bytes,
  template : Bytes,
) -> Result[Bytes, Array[String]] raise GraftError {
  match
    merge_parsed_json(
      parse_merge_json(base, "old template"),
      parse_merge_json(project, "project"),
      parse_merge_json(template, "new template"),
    ) {
    Ok(bytes) => Ok(bytes)
    Err(conflicts) => Err(conflicts.map(conflict => conflict.pointer))
  }
}

///|
/// Decode the paths of files that opt in to structural JSON merging.
pub fn decode_json_merge_paths(text : String) -> Array[String] raise GraftError {
  parse_json_merge_paths(open_archive(text, "moongraft.json-merge"))
}

///|
fn parse_json_merge_paths(payload : Json) -> Array[String] raise GraftError {
  guard payload is Array(entries) &&
    !entries.is_empty() &&
    entries.length() <= 2048 else {
    raise InvalidArchive("expected 1–2048 JSON merge paths")
  }
  entries.map(entry => {
    guard entry is String(path) else {
      raise InvalidArchive("expected a JSON merge path")
    }
    path
  })
}

///|
priv struct JsonFileMerge {
  path : String
  kind : ChangeKind
  output : File?
  conflicts : Array[JsonFieldConflict]
} derive(Debug, Eq)

///|
fn prepare_json_file(
  path : String,
  base : File?,
  project : File?,
  template : File?,
  window_diff : Bool,
  resolutions~ : Map[String, JsonFieldResolution] = Map([]),
) -> JsonFileMerge raise GraftError {
  fn parse(file : File?, side : String) -> Json? raise GraftError {
    match file {
      Some(file) => Some(parse_merge_json(file.content, side + " " + path))
      None => None
    }
  }
  let base_json = parse(base, "old template")
  let project_json = parse(project, "project")
  let template_json = parse(template, "new template")
  if (base, project, template, base_json, project_json, template_json)
    is (Some(b), Some(p), Some(t), Some(bj), Some(pj), Some(tj)) &&
    b != p &&
    b != t &&
    p != t {
    return match merge_parsed_json(bj, pj, tj, resolutions~) {
      Ok(content) => {
        let executable = if p.executable == b.executable {
          t.executable
        } else {
          p.executable
        }
        {
          path,
          kind: MergedJson,
          output: Some(File::new(path, content, executable~)),
          conflicts: [],
        }
      }
      Err(conflicts) =>
        { path, kind: Conflict(JsonConflict), output: None, conflicts, }
    }
  }
  let (kind, output) = classify(base, project, template, window_diff)
  { path, kind, output, conflicts: [], }
}
