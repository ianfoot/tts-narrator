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
