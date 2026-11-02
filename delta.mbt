///|
/// A change to the resulting project, distinct from template merge provenance.
pub(all) enum OutputChange {
  Added(String, Int32, Bool)
  Removed(String, Int32, Bool)
  Modified(String, Int32, Int32, Bool, Bool, Bool)
} derive(Debug, Eq)

///|
pub extend OutputChange with @debug.Debug::{to_repr}

///|
pub extend OutputChange with Eq::{equal, not_equal}

///|
/// Return the actual effect of a fully resolved plan. Modified records contain
/// path, old/new byte counts, old/new executable flags, and whether either
/// version is binary. A mode-only edit is included; unchanged files are absent.
pub fn Plan::output_changes(
  self : Plan,
) -> Array[OutputChange] raise GraftError {
  let result = self.materialize()
  let changes = []
  for path in all_paths([self.current, result]) {
    match (self.current.get(path), result.get(path)) {
      (None, Some(file)) =>
        changes.push(Added(path, file.content.length(), file.executable))
      (Some(file), None) =>
        changes.push(Removed(path, file.content.length(), file.executable))
      (Some(before), Some(after)) if before != after =>
        changes.push(
          Modified(
            path,
            before.content.length(),
            after.content.length(),
            before.executable,
            after.executable,
            !is_text(before.content) || !is_text(after.content),
          ),
        )
      _ => ()
    }
  }
  changes
}

///|
/// Stable, content-free output preview for CI and code review.
pub fn Plan::output_json(self : Plan) -> String raise GraftError {
  let rows = self
    .output_changes()
    .map(change => {
      match change {
        Added(path, size, mode) =>
          Json::array([
            Json::string("add"),
            Json::string(path),
            Json::number(size.to_double()),
            Json::boolean(mode),
          ])
        Removed(path, size, mode) =>
          Json::array([
            Json::string("remove"),
            Json::string(path),
            Json::number(size.to_double()),
            Json::boolean(mode),
          ])
        Modified(path, old_size, new_size, old_mode, new_mode, binary) =>
          Json::array([
            Json::string("modify"),
            Json::string(path),
            Json::number(old_size.to_double()),
            Json::number(new_size.to_double()),
            Json::boolean(old_mode),
            Json::boolean(new_mode),
            Json::boolean(binary),
          ])
      }
    })
  archive("moongraft.output", Json::array(rows))
}
