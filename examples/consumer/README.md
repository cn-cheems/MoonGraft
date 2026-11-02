# Independent consumer

Run `moon run scripts/package-check.mbtx --portable-only` from the repository root.
This packages MoonGraft locally, extracts its archive into a temporary workspace,
and runs this separate module against the extracted library on Wasm, Wasm-GC and
JavaScript. Without `--portable-only`, it also executes the native consumer.

The workspace resolves the unpublished MoonGraft dependency locally; the public
async dependency still needs to be available in the registry/cache. This is not a
claim of zero-network dependency installation or a Mooncakes publication test.

The example exercises public APIs for baseline provenance, lossless plan archives,
protected policy preparation, preservation of business files, refresh and rollback.
