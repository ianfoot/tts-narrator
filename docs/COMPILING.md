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
fvm dart compile exe bin/main.dart --output build/gemini-tts-narrator
```

The AOT compiler follows the entrypoint's import graph, so only the CLI and its
libraries are compiled — the Flutter entry point `lib/main.dart` (and any
Flutter/dart:ui code) is not included.

`build/` is already in `.gitignore`, so the binary stays out of version control.

## Verify (no API cost)

```bash
file build/gemini-tts-narrator          # expect: Mach-O 64-bit executable arm64
build/gemini-tts-narrator --help
build/gemini-tts-narrator --input story.txt --voice Callirrhoe --dry-run   # chunk plan only
```

## Platform notes

- **Host-target build:** `dart compile exe` targets the host OS/architecture
  (this repo builds macOS arm64 by default). The output is not portable to
  other OS/CPU combinations.
- **Cross-compiling:** `--target-os {android,fuchsia,ios,linux,macos,windows}`
  and `--target-arch {arm,arm64,x64,...}` are supported for best-effort
  cross-builds. Realistically, build on each target (or in CI) for distribution.
- The single-file executable is only for the **CLI**. A future macOS GUI would
  instead be built with `flutter build macos`.

## Runtime notes

- Prefer the `OPENROUTER_API_KEY` environment variable over `--api-key`:
  command-line arguments are visible in `ps` output.
- The binary behaves identically to `fvm dart run bin/main.dart -- ...` — all
  options in `--help` apply. `output/` is still created relative to the current
  working directory.