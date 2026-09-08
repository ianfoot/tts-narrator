import 'package:flutter/foundation.dart';

/// The platform-dispatched command slots: nullable callbacks the platform
/// shell wires to native actions and that in-app controls (toolbar, menu bar)
/// dispatch. Held apart from the app controller so it stays free of platform
/// wiring.
class PlatformCommands {
  VoidCallback? onOpen;

  VoidCallback? onNarrate;

  VoidCallback? onCancel;

  VoidCallback? onPreferences;

  /// Mirrors the toolbar toggle so non-macOS platforms can bind the same
  /// action to an in-app control.
  VoidCallback? onToggleSettingsPanel;

  /// Mirrors the controller's folder-picker entry point so the menu bar and
  /// any key binding dispatch through one slot.
  VoidCallback? onSetOutputFolder;
}