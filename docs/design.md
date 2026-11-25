# MoonGraft v0.1 design

MoonGraft upgrades an existing project from an explicitly recorded, rendered
template baseline to a new rendered template. The directory-level lifecycle
works with committed templates, versioned literal rendering, and trees
produced by an external generator.

## Users and complete workflows

1. A platform team updates a shared service template's CI and build configuration.
   Each service records the rendered v1 baseline, plans against rendered v2,
   reviews retained customizations and conflicts, explicitly resolves overlaps,
   and exports a complete candidate directory for the service's normal tests.
2. An open-source organization updates release files across libraries. Each
   library retains its own sources and documentation, reviews template additions
   and deletions, and advances its baseline only alongside the exported result.
3. An application developer adopts a new starter version after customizing it.
   Independent text edits merge; delete/modify and add/add conflicts require a
   decision. A stale project snapshot invalidates a previously reviewed plan.

## First independently useful milestone

- Pure MoonBit immutable trees, explicit template identity/revision and baseline.
- Directory-level three-way planning and conservative line-level text merging.
- Add/add, modify/modify and delete/modify conflicts; explicit keep-local,
  take-template, custom-file or delete decisions.
- Strict versioned, deterministic, lossless JSON archives for trees, baselines
  and plans; plans are recomputed from archived inputs rather than trusted.
- Snapshot preconditions, provenance reports and rebaselining for the next update.
- A Wasm/native CLI scans actual directories and exports into a new directory.
  It does not overwrite the source or modify Git. An incomplete export remains
  visibly incomplete and can be resumed after verifying every existing file.

## Supported input and boundaries

Regular files with portable ASCII relative paths; UTF-8 text and arbitrary binary
contents; executable mode as an explicit core-model attribute. The filesystem
adapter rejects executable-mode output when it cannot preserve the attribute, symlinks,
special files, nonportable paths, empty directories, and exceeded resource limits.
Root `.git` metadata is explicitly outside the managed tree; no other implicit
ignore rules. Text merging preserves byte encoding, BOM, CRLF and final-newline
state. Malformed UTF-8 and NUL-containing content is treated as binary, never
lossily decoded. Both-side binary changes require an explicit decision.

On POSIX hosts the adapter records executability and normalizes output modes to
0644/0755. On Windows it records no POSIX execute bit and refuses export of a
core-model executable file. Other permission bits, ownership and ACLs are not
part of the managed model.

No template execution, remote downloads, Jinja/Cookiecutter compatibility,
automatic rename inference, schema-aware JSON/YAML merging, permissions/ACL
preservation, in-place updates, multi-writer locking, or crash durability claims.
Export is for a trusted, exclusively accessed local workspace. CI support and
actual execution results must be reported separately.

## Correctness

Unchanged template preserves the project. An unchanged project follows the new
template. Equal edits converge. Unknown project files survive unless they collide
with an upstream addition. Conflicts prevent materialization. Every conflict must
have exactly one valid decision. Invalid decisions and structural collisions
leave the plan unchanged. Plan application compares the entire current tree with
the recorded tree before producing output. Deletions and binary changes are
always explicit. Serialized inputs reject unknown fields/tags and unsupported
versions. Resource bounds fail closed, with actionable diagnostics.

Explicit file moves align the old and local file at the destination before
comparison. Declared moves require one-to-one paths across the two template
snapshots. Local destination occupancy and structural collisions stop planning.
Conflicts and decisions use the destination path, while conflict details retain
the original paths. Freshness checks and rollback use the original project
snapshot. Policy checks use the actual output paths.

Parameterized Git records bind the committed subtree, renderer version and
canonical parameters to the rendered baseline. Creating and adopting projects
replays the pinned baseline. Upgrades render the target revision with the same
recipe, so the merge engine compares three concrete file trees.

## Roadmap

1. Complete local baseline → plan → resolve → export → next-baseline workflow.
2. Extend review output for structural changes and explicit moves.
3. Extend parameterized Git sources with external generator adapters and remote
   version discovery.
4. Batch repository upgrades and CI integration, with measured behavior on real
   consumers before making productivity or performance claims.
