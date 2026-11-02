///|
fn file_json(file : File) -> Json {
  // Hex is byte-preserving, deterministic and independent of Unicode handling.
  Json::array([
    Json::string(file.path),
    Json::string(hex(file.content)),
    Json::boolean(file.executable),
  ])
}

///|
fn hex(content : Bytes) -> String {
  let alphabet = "0123456789abcdef"
  let output = StringBuilder()
  for b in content {
    output.write_char(
      alphabet.code_unit_at(b.to_int() / 16).to_int().unsafe_to_char(),
    )
    output.write_char(
      alphabet.code_unit_at(b.to_int() % 16).to_int().unsafe_to_char(),
    )
  }
  output.to_string()
}

///|
fn unhex(text : String) -> Bytes raise GraftError {
  guard text.length() <= 4194304 && text.length() % 2 == 0 else {
    raise InvalidArchive(
      "file content must be even-length hex, at most 2 MiB decoded",
    )
  }
  let output = []
  let mut value = 0
  for i in 0..<text.length() {
    let c = text.code_unit_at(i).to_int()
    let digit = if c >= 48 && c <= 57 {
      c - 48
    } else if c >= 97 && c <= 102 {
      c - 87
    } else {
      raise InvalidArchive("hex content must use lowercase 0-9/a-f")
    }
    value = value * 16 + digit
    if i % 2 == 1 {
      output.push(value.to_byte())
      value = 0
    }
  }
  Bytes::from_array(output)
}

///|
fn parse_file(value : Json) -> File raise GraftError {
  guard value is Array([String(path), String(content), mode]) else {
    raise InvalidArchive(
      "expected file [path, lowercase-hex-content, executable-boolean]",
    )
  }
  let executable = match mode {
    True => true
    False => false
    _ => raise InvalidArchive("executable must be boolean")
  }
  File::new(path, unhex(content), executable~)
}

///|
fn tree_json(tree : Tree) -> Json {
  Json::array(tree.entries.map(file_json))
}

///|
fn parse_tree(value : Json) -> Tree raise GraftError {
  guard value is Array(files) else {
    raise InvalidArchive("expected file array")
  }
  guard files.length() <= 2048 else {
    raise LimitExceeded("more than 2048 archived files")
  }
  let result = []
  let mut total = 0
  for value in files {
    let file = parse_file(value)
    total += file.content.length()
    guard total <= 16777216 else {
      raise LimitExceeded("archived tree exceeds 16 MiB")
    }
    result.push(file)
  }
  Tree::new(result)
}

///|
fn baseline_json(baseline : Baseline) -> Json {
  Json::array([
    Json::string(baseline.template_id),
    Json::string(baseline.revision),
    tree_json(baseline.tree),
  ])
}

///|
fn parse_baseline(value : Json) -> Baseline raise GraftError {
  guard value is Array([String(id), String(revision), files]) else {
    raise InvalidArchive("expected baseline [template-id, revision, files]")
  }
  track(id, revision, parse_tree(files))
}

///|
fn archive(tag : String, payload : Json) -> String {
  Json::array([Json::string(tag), Json::string("1"), payload]).stringify() +
  "\n"
}

///|
fn open_archive(source : String, tag : String) -> Json raise GraftError {
  guard source.length() <= 160000000 else {
    raise LimitExceeded("archive exceeds 160 million UTF-16 units")
  }
  let value = @json.parse(source, max_nesting_depth=16) catch {
    e => raise InvalidArchive("malformed JSON: " + e.to_string())
  }
  guard value is Array([String(actual), String("1"), payload]) && actual == tag else {
    raise InvalidArchive(
      "expected [\"\{tag}\", \"1\", payload]; unknown versions, fields and tags are rejected",
    )
  }
  payload
}

///|
pub fn Tree::encode(self : Tree) -> String {
  archive("moongraft.tree", tree_json(self))
}

///|
pub fn Tree::decode(source : String) -> Tree raise GraftError {
  parse_tree(open_archive(source, "moongraft.tree"))
}

///|
pub fn Baseline::encode(self : Baseline) -> String {
  archive("moongraft.baseline", baseline_json(self))
}

///|
pub fn Baseline::decode(source : String) -> Baseline raise GraftError {
  parse_baseline(open_archive(source, "moongraft.baseline"))
}

///|
fn decision_json(decision : Decision) -> Json {
  let action = match decision.resolution {
    KeepLocal => Json::array([Json::string("keep-local")])
    TakeTemplate => Json::array([Json::string("take-template")])
    Delete => Json::array([Json::string("delete")])
    Replace(file) => Json::array([Json::string("replace"), file_json(file)])
  }
  Json::array([Json::string(decision.path), action])
}

///|
fn parse_decision(value : Json) -> Decision raise GraftError {
  guard value is Array([String(path), action]) else {
    raise InvalidArchive("expected decision [path, action]")
  }
  let resolution = match action {
    Array([String("keep-local")]) => KeepLocal
    Array([String("take-template")]) => TakeTemplate
    Array([String("delete")]) => Delete
    Array([String("replace"), file]) => Replace(parse_file(file))
    _ =>
      raise InvalidArchive(
        "unknown resolution; expected keep-local, take-template, delete or replace",
      )
  }
  Decision::new(path, resolution)
}

///|
/// A plan archive contains all three inputs and explicit decisions. Decoding
/// recomputes the plan, so hand-edited derived output cannot bypass validation.
pub fn Plan::encode(self : Plan) -> String {
  archive(
    "moongraft.plan",
    Json::array([
      baseline_json(self.baseline),
      tree_json(self.current),
      baseline_json(self.next),
      Json::array(self.decisions.map(decision_json)),
    ]),
  )
}

///|
pub fn Plan::decode(source : String) -> Plan raise GraftError {
  guard open_archive(source, "moongraft.plan")
    is Array([base, current, next, Array(decisions)]) else {
    raise InvalidArchive(
      "expected plan [baseline, current-files, next-baseline, decisions]",
    )
  }
  guard decisions.length() <= 6144 else {
    raise LimitExceeded("more than 6144 decisions")
  }
  let plan = plan_update(
    parse_baseline(base),
    parse_tree(current),
    parse_baseline(next),
  )
  plan.resolve(decisions.map(parse_decision))
}
