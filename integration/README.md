# Real upstream-template adoption case

This is a complete, adapted historical template case, not evidence of unmodified
generator compatibility or an independently deployed business application.

## Fixed source and licence

Upstream: [mizchi/moonbit-template](https://github.com/mizchi/moonbit-template),
Apache-2.0. Its complete Git-tracked blob sets (21 files each, including dotfiles,
documentation, source, interfaces, tests and LICENSE) are vendored as hex archives:

- [old commit 4733b6f](https://github.com/mizchi/moonbit-template/tree/4733b6fe1cf6d9ab51b61e2bbe2643d52d8998d4)
- [new commit 580024a](https://github.com/mizchi/moonbit-template/tree/580024abc60f961eb0b5b866fb5b301f889ec365)

The actual upstream change adds quickcheck property tests and revises CI,
documentation and module metadata. The versions are not authored by MoonGraft.
Each record retains its path, Git mode, blob ID and exact bytes. The runner checks
every blob ID with `git hash-object --stdin`; the capture script can reproduce
the snapshots from a clone containing these commits. The embedded AGENTS/CLAUDE
text is fixture data, not instructions governing MoonGraft development.

## Explicit rendering/adaptation contract

Both revisions use the same recipe and preserve the upstream module name
`mizchi/lib`, source directory `src` and default JavaScript target. No project-name
substitution is needed for this clone-based starter. No template hook is executed.

1. Materialize only the known `CLAUDE.md -> AGENTS.md` symlink as an ordinary copy
   of its target. All other file bytes are initially preserved; unknown link
   targets/modes are rejected. This is adapter behavior, not core symlink support.
2. Run the pinned toolchain's `moon fmt` to migrate `moon.mod.json` and format the
   project. Read back the original complete file set, replacing only that metadata
   path with `moon.mod`; formatter caches are not template files.
3. Use official `moon add --no-update --upgrade` to pin async to 0.22.5 and
   quickcheck to 0.15.1 where that dependency exists. The historical dependency
   manifests cannot be consumed unchanged by this toolchain. No dependencies or
   metadata fields are silently removed.

This is a specific verified adapter recipe. It does not establish general
Cookiecutter/Copier/Jinja compatibility. Upstream source tests produce deprecation
warnings; their test runs deliberately do not use `--deny-warn`. MoonGraft and
the integration runner are strictly compiled with `--deny-warn`.

## Project modifications and independent oracles

The local example app adds `src/billing.mbt` and its business test:
`invoice_total(3, 125) == 375`, using integer cents. It also appends a clearly
marked local README section. These additions are authored demonstration business
logic, not claimed as a real customer deployment.

The runner tests the pre-upgrade project, plans the actual upstream delta,
requires README to be classified as merged, round-trips the plan, and compares
the entire result against a separately constructed expectation: the complete
rendered new template plus the exact business files and local README section.
It also verifies the new baseline and exact rollback. This catches discarded
files, incorrect deletions, corrupted contents and lost local customizations.

The upgraded project's own tests pass (6 tests, including the business test and
upstream quickcheck test with 100 generated examples). Its JavaScript build and
entry point run are checked; the upstream application must print `89`.
Only JavaScript is claimed for this historical template: its entry-point effect
annotation does not compile unchanged for Wasm with the updated async dependency.
MoonGraft's separate core/native verification is not used to imply otherwise.

## Reproduce and inspect

Use MoonBit `0.10.17+d971670cd`, Node.js and Git from the repository root:

```text
moon update
moon run --deny-warn integration/template_case
```

Snapshot data is local. First-time dependency installation may access Mooncakes;
no credentials or private infrastructure are required. Generated projects are
left under the printed temporary directory for inspection. The result contains
23 files. The runner deletes stale success evidence on entry, and writes
`_build/template-case.json` only after all assertions pass, bound to the current
MoonGraft revision and dirty-worktree state. CI runs the case on all three OSes
and uploads this record as `template-case-<OS>`. No performance claim is made.

To recapture source data, clone upstream into `_work/upstream-template` with both
pinned commits, then run `moon run scripts/capture-upstream.mbtx`. This developer
step is not needed to reproduce the committed case.
