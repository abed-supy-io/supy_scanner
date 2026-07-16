# Halide 17.0.x vendored prebuilts

Halide is used at build time only — a host generator binary linked against
`libHalide` emits per-target AOT object files for Sauvola 2D binarization
(`supy_core_binarize_luma` in `SAUVOLA_2D` mode). See
`../../docs/V1-S2-05.2-HALIDE.md` for the full design.

## Layout

After vendoring, this directory contains one subdirectory per host triple
that builds the library:

```
halide-17.0.x/
├── README.md          # this file
├── darwin-arm64/      # macOS arm64 (Apple Silicon)
├── darwin-x86_64/     # macOS x86_64 (Intel; CI fallback)
└── linux-x86_64/      # Linux x86_64 (CI)
```

Each subdirectory holds the extracted contents of the matching
`Halide-17.0.1-…tar.gz` release:

```
<host-triple>/
├── bin/        # `Halide.cmake`, autoscheduler binaries
├── lib/        # libHalide.{dylib,so}, libHalide.a
├── include/    # Halide.h, HalideRuntime.h, etc.
└── share/      # cmake config files
```

## Vendoring procedure (one-time per Halide bump)

1. Fetch from `https://github.com/halide/Halide/releases/tag/v17.0.1`:
   - `Halide-17.0.1-arm-64-osx-<sha>.tar.gz`  → `darwin-arm64/`
   - `Halide-17.0.1-x86-64-osx-<sha>.tar.gz`  → `darwin-x86_64/`
   - `Halide-17.0.1-x86-64-linux-<sha>.tar.gz` → `linux-x86_64/`
2. Verify each tarball's sha256 against the published checksum in the
   release notes. Update the table below with the verified hashes before
   committing.
3. Extract under the matching `<host-triple>/` subdirectory.
4. Drop debug variants: `rm lib/libHalide-*.dbg.*` if present.
5. Stage the three subdirectories and commit. Expected diff: only files
   under `darwin-arm64/`, `darwin-x86_64/`, `linux-x86_64/`.

## Verified checksums

Fill in after vendoring. Do not commit a tree where these are still TBD —
that signals the binaries weren't verified.

| Tarball | sha256 |
|---|---|
| `Halide-17.0.1-arm-64-osx-<sha>.tar.gz`  | TBD |
| `Halide-17.0.1-x86-64-osx-<sha>.tar.gz`  | TBD |
| `Halide-17.0.1-x86-64-linux-<sha>.tar.gz` | TBD |

## Why vendored, not FetchContent

Halide release tarballs are ~50–80 MB each (3× = ~200 MB committed). They
include statically-linked LLVM, so we cannot reasonably build from source
in CI on every commit. Vendoring keeps the build hermetic — no LLVM
toolchain dependency, no network at configure time, byte-identical
generator across machines.

A future ticket (V1-S2-05.5) will move these to Git LFS once CI runners
support LFS pulls; until then they live in the working tree.

## Why not committed yet

The scaffolding (CMake modules, generator source, `SUPY_USE_HALIDE`
option) landed in V1-S2-05.2 first so the integration shape could be
reviewed independently of a ~200 MB binary blob commit. Run the vendoring
procedure above when ready to flip `SUPY_USE_HALIDE=ON` on a real build.
