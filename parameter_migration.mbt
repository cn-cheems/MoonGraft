///|
/// Rules for changing the parameter names and defaults of a render recipe.
pub struct ParameterMigration {
  priv renames : Array[(String, String)]
  priv defaults : Array[(String, String)]
  priv drops : Array[String]
} derive(Debug, Eq)

///|
pub fn ParameterMigration::decode(
  text : String,
) -> ParameterMigration raise GraftError {
  guard text.length() <= 8192 else {
    raise LimitExceeded("parameter migration exceeds 8192 units")
  }
  parse_parameter_migration(open_archive(text, "moongraft.parameter-migration"))
}

///|
fn parse_parameter_migration(
  payload : Json,
) -> ParameterMigration raise GraftError {
  guard payload is Array([Array(renames), Array(defaults), Array(drops)]) &&
    renames.length() <= 16 &&
    defaults.length() <= 16 &&
    drops.length() <= 16 else {
    raise InvalidArchive(
      "expected parameter migration [renames, defaults, drops], at most 16 rules per list",
    )
  }
  let renames = renames.map(row => {
    guard row is Array([String(from), String(to)]) &&
      valid_parameter_name(from) &&
      valid_parameter_name(to) &&
      from != to else {
      raise InvalidArchive("expected parameter rename [old-name, new-name]")
    }
    (from, to)
  })
  let defaults = defaults.map(row => {
    guard row is Array([String(name), String(value)]) &&
      valid_parameter_name(name) &&
      value.length() <= 128 &&
      value.iter().all(c => c.to_int() >= 32 && c != '\u{007f}') else {
      raise InvalidArchive(
        "expected parameter default [name, single-line value]",
      )
    }
    (name, value)
  })
  let drops = drops.map(row => {
    guard row is String(name) && valid_parameter_name(name) else {
      raise InvalidArchive("expected a parameter name to drop")
    }
    name
  })
  renames.sort_by((a, b) => a.0.lexical_compare(b.0))
  defaults.sort_by((a, b) => a.0.lexical_compare(b.0))
  drops.sort_by((a, b) => a.lexical_compare(b))
  { renames, defaults, drops, }
}

///|
fn ParameterMigration::payload(self : ParameterMigration) -> Json {
  fn pairs(values : Array[(String, String)]) -> Json {
    Json::array(
      values.map(pair => {
        Json::array([Json::string(pair.0), Json::string(pair.1)])
      }),
    )
  }
  Json::array([
    pairs(self.renames),
    pairs(self.defaults),
    Json::array(self.drops.map(Json::string)),
  ])
}

///|
pub fn ParameterMigration::encode(self : ParameterMigration) -> String {
  archive("moongraft.parameter-migration", self.payload())
}

///|
/// Apply rules simultaneously to the old recipe. Reject unused rules, collisions,
/// explicit drops paired with a rename, and defaults that replace old values.
pub fn ParameterMigration::apply(
  self : ParameterMigration,
  parameters : RenderParameters,
) -> RenderParameters raise GraftError {
  let old = Map::from_array(parameters.values)
  let renames : Map[String, String] = Map([])
  let drops : Map[String, Bool] = Map([])
  for (from, to) in self.renames {
    guard old.contains(from) && !renames.contains(from) else {
      raise InvalidTemplate("Unknown or repeated rename source: " + from)
    }
    renames[from] = to
  }
  for name in self.drops {
    guard old.contains(name) && !renames.contains(name) && !drops.contains(name) else {
      raise InvalidTemplate("Unknown or repeated migration rule for: " + name)
    }
    drops[name] = true
  }
  let result = []
  let used : Map[String, Bool] = Map([])
  fn record(name : String, value : String) -> Unit raise GraftError {
    guard !used.contains(name) else {
      raise InvalidTemplate(
        "Multiple migration values target parameter: " + name,
      )
    }
    used[name] = true
    result.push((name, value))
  }
  for (name, value) in parameters.values {
    if !drops.contains(name) {
      record(renames.get(name).unwrap_or(name), value)
    }
  }
  for (name, value) in self.defaults {
    guard !old.contains(name) else {
      raise InvalidTemplate(
        "Migration default must introduce a new parameter: " + name,
      )
    }
    record(name, value)
  }
  result.sort_by((a, b) => a.0.lexical_compare(b.0))
  let migrated : RenderParameters = { values: result, }
  guard !result.is_empty() &&
    result.length() <= 16 &&
    migrated.encode().length() <= 512 else {
    raise LimitExceeded(
      "migrated recipe must contain 1–16 parameters and fit within 512 units",
    )
  }
  guard migrated != parameters else {
    raise InvalidTemplate("Migration leaves the parameter recipe unchanged")
  }
  migrated
}

///|
fn render_identity(
  id : String,
) -> (String, String, RenderParameters) raise GraftError {
  guard parse_archive_json(id)
    is Array(
      [
        String(repository),
        String(subdir),
        String("moongraft.render.v1"),
        String(parameters),
      ]
    ) else {
    raise InvalidTemplate(
      "Parameter migration requires two versioned render identities",
    )
  }
  (repository, subdir, RenderParameters::decode(parameters))
}
