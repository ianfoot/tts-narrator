import 'package:flutter/foundation.dart';

/// Centralized platform detection helpers (Phase 1 of Linux support).
///
/// Every widget checks these getters instead of comparing
/// `defaultTargetPlatform` inline, so platform branches have a single source
/// of truth.
bool get isMac => defaultTargetPlatform == TargetPlatform.macOS;

/// True when running on Linux.
bool get isLinux => defaultTargetPlatform == TargetPlatform.linux;

/// True when running on Windows.
bool get isWindows => defaultTargetPlatform == TargetPlatform.windows;

/// Manifest platform tag matching the keys of `voice-config/manifest.json`
/// (`macos` / `linux` / `windows`).
///
/// Used to select which starter voice-config files ship on this platform:
/// macOS-only models (e.g. `mlx_kokoro.json`) are excluded elsewhere. Unknown
/// platforms fall back to the `linux` key (no macOS-only starters).
String get platformTag {
  if (isMac) return 'macos';
  if (isLinux) return 'linux';
  if (isWindows) return 'windows';
  return 'linux';
}