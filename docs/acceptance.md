# Initial repository acceptance

This milestone is intended for a developer evaluating a local template upgrade,
or consuming the core from a MoonBit workspace. It is not a claim of production
deployment, performance superiority or ecosystem uniqueness.

## Reproduce from a clean checkout

The [complete historical upstream-template case](../integration/README.md) is
part of verification. Its adapted project is built, tested and executed on its
JavaScript target; this is distinct from MoonGraft's own multi-target tests.
It does not establish universal generator compatibility or downstream native
support. All compatibility edits and upstream warnings are disclosed there.

```text
moon update
moon run --deny-warn scripts/verify.mbtx
```

The command checks formatting, generated interfaces, strict compilation on all
supported targets, target-specific tests, the real-directory example and an
isolated archive consumer. It fails on a failed child command. Native success
requires tests and example execution, not only compilation.

The example exercises conflict rejection before writing, manual coordination,
business-file preservation, baseline advancement, new-process interrupted-export
recovery, stale-plan diagnostics, decision refresh, protected paths, policy
rejection before directory creation, read-only verification and rollback.

The separate consumer is built from `_build/publish/cn-cheems-moongraft-0.1.0.zip`
inside a new temporary workspace. It confirms public APIs can upgrade, preserve
project files, round-trip the plan, prepare under policy, refresh and roll back.
The source archive is not a replacement for a Git checkout when running the
example: the packager may omit dot-directory fixtures. Clone Git for the complete
reproducible example and workflow sources.

## Interpreting evidence

- `--portable-only` covers Wasm, Wasm-GC and JavaScript; the filesystem CLI runs
  on Wasm. It does not assert native execution on that machine.
- Full CI executes native tests, CLI and consumer on its named OS. Inspect the
  [workflow runs](https://github.com/cn-cheems/MoonGraft/actions/workflows/ci.yml)
  for the exact commit. A pending, skipped or cancelled job is not verification.
- No package publication, release tag or GitHub Release is performed by these
  scripts. Dependency installation can access the public package registry.
- Policies are explicit caller controls. `export-checked` applies one supplied
  policy before export; ordinary `export` deliberately remains available.
- Export requires trusted, exclusive access. It does not provide hostile-process
  confinement, multi-writer locking or power-loss durability.

## Next milestone boundaries

Seek feedback from maintainers upgrading real rendered templates before adding
features. Prioritize explicit rename provenance and generator adapters only after
their archive, refresh and rollback semantics are specified. Measure performance
with real consumers before claiming improvements.
