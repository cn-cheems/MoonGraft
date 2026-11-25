///|
test "remote ref lookup requires the exact advertised name" {
  let oid = "0123456789abcdef0123456789abcdef01234567"
  let other = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let refname = "refs/heads/release"
  let suffix = other + "\trefs/heads/team/" + refname + "\n"
  let row = oid + "\t" + refname + "\n"
  assert_eq(advertised_revision(suffix + row, refname), oid)
  for listing in [suffix, row + row, "not-a-sha\t" + refname, "bad row"] {
    try advertised_revision(listing, refname) catch {
      WorkspaceError(_) => ()
    } noraise {
      _ => fail("Invalid remote listing was accepted")
    }
  }
}
