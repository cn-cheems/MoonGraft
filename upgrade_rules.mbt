///|
/// Declarative operations for one transition between fixed template revisions.
pub struct UpgradeRules {
  priv migration : ParameterMigration?
  priv renames : Array[FileRename]
  priv json_paths : Array[String]
} derive(Debug, Eq)

///|
pub fn UpgradeRules::decode(text : String) -> UpgradeRules raise GraftError {
  guard open_archive(text, "moongraft.upgrade-rules")
    is Array([migration, moves, paths]) else {
    raise InvalidArchive(
      "expected upgrade rules [parameter-migration or null, file-moves, JSON-paths]",
    )
  }
  let migration = match migration {
    Null => None
    value => Some(parse_parameter_migration(value))
  }
  let renames = parse_renames(moves)
  renames.sort_by((a, b) => a.from_path.lexical_compare(b.from_path))
  let json_paths = match paths {
    Array([]) => []
    value => parse_json_merge_paths(value)
  }
  json_paths.sort_by((a, b) => a.lexical_compare(b))
  { migration, renames, json_paths, }
}

///|
pub fn UpgradeRules::encode(self : UpgradeRules) -> String {
  archive(
    "moongraft.upgrade-rules",
    Json::array([
      match self.migration {
        Some(migration) => migration.payload()
        None => Json::null()
      },
      rename_rows(self.renames),
      Json::array(self.json_paths.map(Json::string)),
    ]),
  )
}

///|
pub fn UpgradeRules::parameter_migration(
  self : UpgradeRules,
) -> ParameterMigration? {
  self.migration
}

///|
pub fn Plan::upgrade_rules(self : Plan) -> UpgradeRules {
  {
    migration: self.parameter_migration,
    renames: self.renames(),
    json_paths: self.json_merge_paths(),
  }
}

///|
pub fn plan_upgrade_with_rules(
  baseline : Baseline,
  current : Tree,
  next : Baseline,
  rules : UpgradeRules,
) -> Plan raise GraftError {
  plan_update_for_diff(
    baseline,
    current,
    next,
    rules.renames,
    true,
    parameter_migration?=rules.migration,
    json_paths=rules.json_paths,
  )
}
