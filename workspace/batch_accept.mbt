///|
/// Accept all verified candidates using their captured source records.
/// Revalidate every target against Git before creating any output. The new
/// directory contains source records and a final acceptance.json marker.
/// Callers must run each project's business tests before invoking this operation.
pub async fn accept_git_batch(batch : String, destination : String) -> Json {
  require_outside(destination, batch)
  verify_git_batch(batch)
  let entries = parse_git_batch(
    @utf8.decode(read_bytes(batch + "/manifest.json"), ignore_bom=false),
  )
  let records = []
  let rows = []
  for entry in entries {
    if @fs.exists(entry.project) {
      require_outside(destination, entry.project)
    }
    let directory = batch + "/" + entry.id
    let source = GitSource::decode(read_text(directory + "/source.json"))
    require_outside(destination, source.repository)
    let plan = @graft.Plan::decode(read_text(directory + "/plan.json"))
    let target = source.accept_upgrade(
      plan,
      scan(directory + "/candidate/project"),
    )
    records.push((entry.id, target))
    rows.push(
      Json::object({
        "id": Json::string(entry.id),
        "revision": Json::string(target.baseline.revision),
        "source": Json::string(entry.id + ".json"),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moongraft.git-batch-acceptance.v1"),
    "projects": Json::array(rows),
  })
  @fs.mkdir(destination)
  for (id, source) in records {
    write_new(destination + "/" + id + ".json", source.encode())
  }
  write_new(destination + "/acceptance.json", report.stringify() + "\n")
  report
}
