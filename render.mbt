///|
/// Canonical parameters for the version 1 literal substitution renderer.
pub struct RenderParameters {
  priv values : Array[(String, String)]
} derive(Debug, Eq)

///|
fn valid_parameter_name(name : String) -> Bool {
  !name.is_empty() &&
  name.length() <= 32 &&
  name
  .iter()
  .all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')
}

///|
/// Decode ["moongraft.parameters","1",[[name,value],...]], then sort by name.
pub fn RenderParameters::decode(
  text : String,
) -> RenderParameters raise GraftError {
  guard text.length() <= 8192 else {
    raise LimitExceeded("render parameter input exceeds 8192 units")
  }
  guard open_archive(text, "moongraft.parameters") is Array(rows) &&
    rows.length() > 0 &&
    rows.length() <= 16 else {
    raise InvalidArchive("expected 1–16 render parameter pairs")
  }
  let seen : Map[String, Bool] = Map([])
  let values = []
  for row in rows {
    guard row is Array([String(name), String(value)]) &&
      valid_parameter_name(name) &&
      !seen.contains(name) else {
      raise InvalidArchive(
        "expected distinct render parameter names using a-z, 0-9 or _",
      )
    }
    guard value.length() <= 128 &&
      value.iter().all(c => c.to_int() >= 32 && c != '\u{007f}') else {
      raise InvalidArchive(
        "render parameter must be single-line and at most 128 units: " + name,
      )
    }
    seen[name] = true
    values.push((name, value))
  }
  values.sort_by((a, b) => a.0.lexical_compare(b.0))
  let parameters = { values, }
  guard parameters.encode().length() <= 512 else {
    raise LimitExceeded("canonical render parameters exceed 512 units")
  }
  parameters
}

///|
pub fn RenderParameters::encode(self : RenderParameters) -> String {
  archive(
    "moongraft.parameters",
    Json::array(
      self.values.map(pair => {
        Json::array([Json::string(pair.0), Json::string(pair.1)])
      }),
    ),
  )
}

///|
fn render_tokens(
  input : String,
  parameters : Map[String, String],
  limit : Int32,
  path : String,
) -> String raise GraftError {
  let output = StringBuilder()
  let mut size = 0
  fn append(part : StringView) -> Unit raise GraftError {
    size += part.length()
    guard size <= limit else {
      raise LimitExceeded("rendered output exceeds its limit: " + path)
    }
    output.write_view(part)
  }
  let mut literal = true
  for part in input.split("@{") {
    if literal {
      append(part)
      literal = false
      continue
    }
    guard part.split_once("}") is Some((name, trailing)) &&
      parameters.get(name.to_owned()) is Some(value) else {
      raise InvalidTemplate(
        "Unknown or incomplete render placeholder in " + path,
      )
    }
    append(value[:])
    append(trailing)
  }
  output.to_string()
}

///|
/// Render an immutable template tree using its committed moongraft.render.json
/// descriptor. Paths and explicitly selected UTF-8 files use literal tokens.
/// Ordinary file contents keep their exact bytes and executable bit.
pub fn Tree::render_parameters(
  self : Tree,
  parameters : RenderParameters,
) -> Tree raise GraftError {
  let descriptor = "moongraft.render.json"
  guard self.get(descriptor) is Some(config) else {
    raise InvalidTemplate("Missing template render descriptor: " + descriptor)
  }
  let config_text = decode_render_text(config)
  guard config_text.length() <= 65536 else {
    raise LimitExceeded("render descriptor exceeds 65536 units")
  }
  guard open_archive(config_text, "moongraft.render")
    is Array([Array(names), Array(text_paths)]) &&
    names.length() == parameters.values.length() &&
    text_paths.length() <= 2047 else {
    raise InvalidTemplate(
      "Expected render descriptor [parameter-names, text-file-paths] with the exact supplied parameters",
    )
  }
  let values = Map::from_array(parameters.values)
  let declared : Map[String, Bool] = Map([])
  for entry in names {
    guard entry is String(name) &&
      values.contains(name) &&
      !declared.contains(name) else {
      raise InvalidTemplate(
        "Render descriptor parameter names must be distinct and match the supplied names",
      )
    }
    declared[name] = true
  }
  let selected : Map[String, Bool] = Map([])
  for entry in text_paths {
    guard entry is String(path) &&
      path != descriptor &&
      self.get(path) is Some(_) &&
      !selected.contains(path) else {
      raise InvalidTemplate(
        "Render descriptor lists an invalid, missing or duplicate text file",
      )
    }
    selected[path] = true
  }
  let files = []
  let mut remaining = 16777216
  for file in self.entries {
    if file.path == descriptor {
      continue
    }
    let path = render_tokens(file.path, values, 240, file.path)
    guard path.to_lower() != descriptor else {
      raise InvalidTemplate(
        "Rendered file would occupy the descriptor path: " + file.path,
      )
    }
    let content = if selected.contains(file.path) {
      @utf8.encode(
        render_tokens(decode_render_text(file), values, 2097152, file.path),
      )
    } else {
      file.content
    }
    remaining -= content.length()
    guard remaining >= 0 else {
      raise LimitExceeded("rendered tree exceeds 16 MiB")
    }
    files.push(File::new(path, content, executable=file.executable))
  }
  guard !files.is_empty() else {
    raise InvalidTemplate("Rendered template has no project files")
  }
  Tree::new(files)
}

///|
fn decode_render_text(file : File) -> String raise GraftError {
  for byte in file.content {
    guard byte != 0 else {
      raise InvalidTemplate("Render text contains NUL: " + file.path)
    }
  }
  @utf8.decode(file.content, ignore_bom=false) catch {
    _ => raise InvalidTemplate("Render text must be UTF-8: " + file.path)
  }
}
