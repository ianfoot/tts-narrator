# GUI-only build instructions

This project is now **GUI-only** with no CLI interface. The Flutter macOS application is the only entry point.

## Prerequisites

- `fvm` with the project SDK (see `.fvmrc` → Flutter 3.47.1, Dart 3.13.1).
- Xcode installed (required for macOS app compilation).

## Build and run

From the project root:

```bash
fvm flutter run
```

Or build the macOS app separately:

```bash
cd app
fvm flutter build macos
```