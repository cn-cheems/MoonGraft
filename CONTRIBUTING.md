# Contributing

MoonGraft's initial scope is local upgrades between explicitly rendered templates.
Open an issue describing the repeated user task before adding another command.
Keep correctness logic in the portable core and filesystem behavior in `workspace`.

Use MoonBit `0.10.17+d971670cd`; install Node.js for JavaScript tests. Native
execution additionally needs the platform C toolchain (MSVC C++ Build Tools and
Windows SDK on Windows). Do not replace `.mbtx` automation with shell scripts.

From the root of a clean checkout:

```text
moon update
moon fmt
moon fmt scripts/demo.mbtx scripts/verify.mbtx scripts/package-check.mbtx
moon -C examples/consumer fmt
moon info --target all
moon run --deny-warn scripts/verify.mbtx
```

For local development without a native compiler, use `--portable-only` on the
verification script. This does not establish native runtime support. CI runs the
full command on each configured OS, including actual native CLI and archive
consumer execution. Inspect the run for the exact revision; queued/cancelled jobs
are not passing evidence.

Add implementation, boundary tests, a runnable example or usage documentation and
generated interfaces in the same capability commit. Never hand-edit `.mbti` files.
Prefer black-box tests and preservation/determinism properties. Unsupported input
must fail with a diagnostic, without deleting or dropping the input.

Before committing, inspect `git status`, stage explicit paths, review
`git diff --cached` and run `git diff --cached --check`. Preserve unrelated changes
and use your configured identity. Submit substantive, reviewable changes; no empty
commits or artificial splits. Track third-party sources and licenses in
`THIRD_PARTY.md` and the relevant fixture source file.

Public errors, enum variants, record fields, archive tags and CLI exit behavior
are API changes even before 1.0. Keep the existing version-1 archives readable;
introduce an explicitly versioned format for incompatible changes.

The package verification script leaves its temporary workspace for inspection.
The archive consumer is a separate module resolved against the extracted package
via `moon.work`; it does not prove public registry publication. Public runtime
dependencies may need network/cache access.
