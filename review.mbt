///|
/// Generate an empty review bound to this exact plan, including prior decisions.
pub fn Plan::review_template(self : Plan) -> String {
  archive(
    "moongraft.review",
    Json::array([Json::string(self.encode()), Json::array([])]),
  )
}

///|
/// Apply all review decisions atomically. Reviews of a different or previously
/// resolved plan are rejected before any decision is applied.
pub fn Plan::resolve_review(
  self : Plan,
  source : String,
) -> Plan raise GraftError {
  guard open_archive(source, "moongraft.review")
    is Array([String(expected), Array(decisions)]) else {
    raise InvalidArchive("expected review [exact-plan-archive, decisions]")
  }
  guard expected == self.encode() else {
    raise InvalidArchive(
      "review belongs to a different plan; regenerate and review again",
    )
  }
  guard decisions.length() <= 6144 else {
    raise LimitExceeded("more than 6144 review decisions")
  }
  self.resolve(decisions.map(parse_decision))
}
