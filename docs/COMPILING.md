# Compiling the CLI to a native executable

The narration CLI (`packages/cli`) is pure Dart — it depends only on the
`tts_narrator_core` package and the standard library, never Flutter or any
native plugin. It can therefore be compiled ahead-of-time into a single,
self-contained native executable with no Dart runtime installed on the target
machine.

## Prerequisites

- `fvm` with the project SDK (see `.fvmrc` → Flutter 3.47.1, Dart 3.13.1).
- Xcode command-line tools (for the `clang` linkage step). Verify with:
  `xcrun --find clang`.

## Build

Run from the `packages/cli` directory so the workspace resolves
`tts_narrator_core` correctly:

```bash
cd packages/cli
fvm dart compile exe bin/main.dart -o ../../build/tts-narrator
```

The AOT compiler follows the entrypoint's import graph, so only the CLI and
`tts_narrator_core` are compiled — the Flutter/GUI package (`app/`) and any
GUI-only plugins (`audioplayers`, `file_selector`, `objective_c`) are not
included.

`build/` is already in `.gitignore`, so the binary stays out of version control.

## Verify (no API cost)

Run from the repo root so `output/` and `story.txt` resolve as usual:

```bash
file build/tts-narrator      # expect: Mach-O 64-bit executable arm64
./build/tts-narrator --help
./build/tts-narrator --input story.txt --voice Callirrhoe --dry-run   # chunk plan only
```

## Platform notes

- **Host-target build:** `dart compile exe` targets the host OS/architecture
  (this repo builds macOS arm64 by default). The output is not portable to
  other OS/CPU combinations.
- **Cross-compiling:** `--target-os {android,fuchsia,ios,linux,macos,windows}`
  and `--target-arch {arm,arm64,x64,...}` are supported for best-effort
  cross-builds. Realistically, build on each target (or in CI) for distribution.
- The single-file executable is only for the **CLI**. The macOS GUI is built
  separately with `cd app && fvm flutter build macos`.

## Why not `dart build cli`

The GUI package (`app/`) pulls in native build-hook packages (`objective_c` via
`audioplayers`). Those live only in `app/`'s dependency graph, so they no
longer affect the CLI — `dart compile exe` works here without needing
`dart build cli` (which produced a `bundle/` with a `.dylib`). If a plugin is
ever added to the CLI's graph, the build may fail with "does not support build
hooks"; the fix is to keep the CLI's dependency set pure Dart.

## Runtime notes

- Prefer the `OPENROUTER_API_KEY` environment variable over `--api-key`:
  command-line arguments are visible in `ps` output.
- The binary behaves identically to
  `cd packages/cli && fvm dart run bin/main.dart -- ...` — all options in
  `--help` apply. `output/` is still created relative to the current working
  directory (so run from the repo root as above).