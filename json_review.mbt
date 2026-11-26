///|
/// Select a side of a JSON conflict, or supply one strict JSON value.
/// Selecting a side where a member is absent removes that member.
pub(all) enum JsonFieldResolution {
  KeepLocalField
  TakeTemplateField
  SetJsonField(String)
} derive(Debug, Eq)

///|
pub struct JsonFieldDecision {
  pointer : String
  resolution : JsonFieldResolution
} derive(Debug, Eq)

///|
pub fn JsonFieldDecision::new(
  pointer : String,
  resolution : JsonFieldResolution,
) -> JsonFieldDecision {
  { pointer, resolution, }
}

///|
/// Each present member holds the exact JSON value as text. None denotes an
/// absent member, distinct from Some("null").
pub struct JsonFieldConflict {
  pointer : String
  base : String?
  project : String?
  template : String?
} derive(Debug, Eq)

///|
fn Plan::find_json_conflict(
  self : Plan,
  path : String,
  pointer : String,
) -> JsonFieldConflict? {
  if self.json_changes.get(path) is Some(change) {
    for conflict in change.conflicts {
      if conflict.pointer == pointer {
        return Some(conflict)
      }
    }
  }
  None
}

///|
pub fn Plan::json_field_conflict(
  self : Plan,
  path : String,
  pointer : String,
) -> JsonFieldConflict raise GraftError {
  guard self.find_json_conflict(path, pointer) is Some(conflict) else {
    raise InvalidDecision(
      path,
      "not a conflicting JSON pointer: " + Json::string(pointer).stringify(),
    )
  }
  conflict
}

///|
fn Plan::decision_at(self : Plan, path : String) -> ReviewDecision? {
  for decision in self.decisions {
    if decision.path == path {
      return Some(decision)
    }
  }
  None
}

///|
/// Add or replace field decisions at the given pointers. Other reviewed
/// pointers in the same file remain selected.
pub fn Plan::resolve_json_fields(
  self : Plan,
  path : String,
  fields : Array[JsonFieldDecision],
) -> Plan raise GraftError {
  self.resolve_combined([{ path, resolution: JsonFields(fields), }])
}

///|
pub fn Plan::json_field_decisions(
  self : Plan,
  path : String,
) -> Array[JsonFieldDecision] {
  match self.decision_at(path) {
    Some({ resolution: JsonFields(fields), .. }) => fields.copy()
    _ => []
  }
}

///|
/// Return the JSON Pointers still requiring a decision in this file.
pub fn Plan::unresolved_json_pointers(
  self : Plan,
  path : String,
) -> Array[String] {
  match self.decision_at(path) {
    Some({ resolution: JsonFields(fields), .. }) =>
      self
      .json_conflicts(path)
      .filter(pointer => !fields.any(field => field.pointer == pointer))
    Some(_) => []
    None => self.json_conflicts(path)
  }
}

///|
fn Plan::normalize_json_decisions(
  self : Plan,
  path : String,
  fields : Array[JsonFieldDecision],
) -> ReviewResolution raise GraftError {
  guard !fields.is_empty() && fields.length() <= 256 else {
    raise InvalidDecision(path, "expected 1–256 JSON field decisions")
  }
  let combined : Map[String, JsonFieldResolution] = Map([])
  if self.decision_at(path) is Some({ resolution: JsonFields(previous), .. }) {
    for field in previous {
      combined[field.pointer] = field.resolution
    }
  }
  let seen : Map[String, Bool] = Map([])
  for field in fields {
    ignore(self.json_field_conflict(path, field.pointer))
    guard !seen.contains(field.pointer) else {
      raise InvalidDecision(path, "duplicate JSON field decision")
    }
    seen[field.pointer] = true
    let resolution = match field.resolution {
      SetJsonField(value) => {
        let parsed = parse_merge_json(
          @utf8.encode(value),
          "reviewed JSON value in " + path,
        )
        let canonical = canonical_merge_json(parsed).stringify()
        guard @utf8.encode(canonical).length() <= 2097152 else {
          raise LimitExceeded("reviewed JSON value exceeds 2 MiB in " + path)
        }
        SetJsonField(canonical)
      }
      other => other
    }
    combined[field.pointer] = resolution
  }
  let result = combined
    .iter()
    .map(pair => JsonFieldDecision::new(pair.0, pair.1))
    .to_array()
  result.sort_by((a, b) => a.pointer.lexical_compare(b.pointer))
  JsonFields(result)
}

///|
fn json_field_rows(fields : Array[JsonFieldDecision]) -> Json {
  Json::array(
    fields.map(field => {
      let pointer = Json::string(field.pointer)
      Json::array(
        match field.resolution {
          KeepLocalField => [pointer, Json::string("keep-local")]
          TakeTemplateField => [pointer, Json::string("take-template")]
          SetJsonField(value) =>
            [pointer, Json::string("value"), Json::string(value)]
        },
      )
    }),
  )
}

///|
fn parse_json_field_rows(
  rows : Array[Json],
) -> Array[JsonFieldDecision] raise GraftError {
  guard !rows.is_empty() && rows.length() <= 256 else {
    raise InvalidArchive("expected 1–256 JSON field decisions")
  }
  rows.map(row => {
    match row {
      Array([String(pointer), String("keep-local")]) =>
        JsonFieldDecision::new(pointer, KeepLocalField)
      Array([String(pointer), String("take-template")]) =>
        JsonFieldDecision::new(pointer, TakeTemplateField)
      Array([String(pointer), String("value"), String(value)]) =>
        JsonFieldDecision::new(pointer, SetJsonField(value))
      _ =>
        raise InvalidArchive(
          "expected [pointer, keep-local|take-template] or [pointer, value, JSON text]",
        )
    }
  })
}
