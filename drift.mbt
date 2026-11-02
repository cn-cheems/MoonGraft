///|
/// Content-free explanation of why a recorded project snapshot is stale.
pub(all) enum ProjectDrift {
  NewPath(String)
  MissingPath(String)
  Changed(String, Bool, Bool)
} derive(Debug, Eq)

///|
pub extend ProjectDrift with @debug.Debug::{to_repr}

///|
pub extend ProjectDrift with Eq::{equal, not_equal}

///|
/// Compare the recorded project with a newly scanned tree. Changed flags denote
/// byte changes and executable-attribute changes respectively. Sorted by path.
pub fn Plan::project_drift(self : Plan, current : Tree) -> Array[ProjectDrift] {
  let result = []
  for path in all_paths([self.current, current]) {
    match (self.current.get(path), current.get(path)) {
      (None, Some(_)) => result.push(NewPath(path))
      (Some(_), None) => result.push(MissingPath(path))
      (Some(before), Some(after)) if before != after =>
        result.push(
          Changed(
            path,
            before.content != after.content,
            before.executable != after.executable,
          ),
        )
      _ => ()
    }
  }
  result
}

///|
pub fn Plan::drift_json(self : Plan, current : Tree) -> String {
  archive(
    "moongraft.drift",
    Json::array(
      self
      .project_drift(current)
      .map(change => {
        match change {
          NewPath(path) =>
            Json::array([Json::string("add"), Json::string(path)])
          MissingPath(path) =>
            Json::array([Json::string("remove"), Json::string(path)])
          Changed(path, bytes, mode) =>
            Json::array([
              Json::string("change"),
              Json::string(path),
              Json::boolean(bytes),
              Json::boolean(mode),
            ])
        }
      }),
    ),
  )
}
