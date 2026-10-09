import 'package:flutter/foundation.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Centralized platform detection helpers. Widgets check these getters instead
/// of comparing `defaultTargetPlatform` inline, so platform branches have a
/// single source of truth.
bool get isMac => defaultTargetPlatform == TargetPlatform.macOS;

/// True when running on Linux.
bool get isLinux => defaultTargetPlatform == TargetPlatform.linux;

/// True when running on Windows.
bool get isWindows => defaultTargetPlatform == TargetPlatform.windows;

/// Manifest platform tag matching the keys of `voice-config/manifest.json`
/// (`macos` / `linux` / `windows`), sourced from the core constants that also
/// define those keys.
///
/// Used to select which starter voice-config files ship on this platform:
/// macOS-only models (e.g. `mlx_kokoro.json`) are excluded elsewhere. Unknown
/// platforms fall back to the `linux` key (no macOS-only starters).
String get platformTag {
  if (isMac) return kPlatformTagMacos;
  if (isLinux) return kPlatformTagLinux;
  if (isWindows) return kPlatformTagWindows;
  return kPlatformTagLinux;
}

/// Platform-appropriate accelerator label for a key: `⌘O` on macOS and
/// `Ctrl+O` elsewhere, e.g. `acceleratorLabel('N')` → `Ctrl+N`.
///
/// Used to annotate tooltips without hardcoding macOS-style shortcuts for all
/// platforms.
String acceleratorLabel(String key, {bool shift = false}) {
  final modifier = isMac ? '⌘' : 'Ctrl+';
  final shiftLabel = isMac ? '⇧' : 'Shift+';
  return shift ? '$modifier$shiftLabel$key' : '$modifier$key';
}
