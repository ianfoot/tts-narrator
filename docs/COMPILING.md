  # Compiling the CLI to a native executable

The narration CLI is pure Dart (the `bin/` → `lib/src` path only uses
`dart:io`, `dart:convert`, `dart:typed_data`; it never imports the Flutter
stub). It can therefore be compiled ahead-of-time into a single, self-contained
native executable with no Dart runtime installed on the target machine.

## Prerequisites

- `fvm` with the project SDK (see `.fvmrc` → Flutter 3.47.1, Dart 3.13.1).
- Xcode command-line tools (for the `clang` linkage step). Verify with:
  `xcrun --find clang`.

## Build

```bash
fvm dart build cli -o build/cli
```

`dart build cli` (Dart 3.13+) compiles the CLI with any native build hooks
(linker + asset copy) and produces a self-contained bundle:
`build/cli/<host-triple>/bundle/bin/main` plus any dynamic libraries (e.g.
`lib/objective_c.dylib`).

The AOT compiler follows the entrypoint's import graph, so only the CLI and its
libraries are compiled — the Flutter entry point `lib/main.dart` (and any
Flutter/dart:ui code) is not included.

> Using `dart compile exe` here currently fails once `audioplayers` (GUI dep) is
> in the graph, because it transitively brings `objective_c` (a native build-hook
> package) which `compile exe` cannot run. Keep using `dart build cli`.

`build/` is already in `.gitignore`, so the bundle stays out of version control.

## Verify (no API cost)

```bash
file build/cli/macos_arm64/bundle/bin/main   # expect: Mach-O 64-bit executable arm64
build/cli/macos_arm64/bundle/bin/main --help
build/cli/macos_arm64/bundle/bin/main --input story.txt --voice Callirrhoe --dry-run   # chunk plan only
```

## Platform notes

- **Host-target build:** `dart build cli` targets the host OS/architecture
  (this repo builds macOS arm64 by default). The bundle is not portable to
  other OS/CPU combinations; run the link hook on each target (or in CI).
  Use `--target-os`/`--target-arch` for best-effort cross-builds.
- The native CLI bundle is only for the **CLI**. A future macOS GUI would
  instead be built with `flutter build macos`.

## Runtime notes

- Prefer the `OPENROUTER_API_KEY` environment variable over `--api-key`:
  command-line arguments are visible in `ps` output.
- The binary behaves identically to `fvm dart run bin/main.dart -- ...` — all
  options in `--help` apply. `output/` is still created relative to the current
  working directory.