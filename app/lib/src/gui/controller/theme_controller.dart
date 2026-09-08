import 'package:flutter/foundation.dart';

import '../theme/app_tokens.dart' show AppThemeMode;

/// Owns the user's appearance choice for the TTS Narrator GUI.
///
/// The mode defaults to following the OS ([AppThemeMode.system]) and is exposed
/// both as a plain value and via [themeNotifier] for appearance-only widgets
/// (e.g. the app root theme resolution) that should not rebuild on every other
/// controller write.
///
/// [AppController] forwards its `themeMode` surface to this controller and
/// re-broadcasts notifications, so existing call sites keep a single change
/// stream.
class ThemeController extends ChangeNotifier {
  AppThemeMode _themeMode = AppThemeMode.system;

  /// The user's appearance choice ([AppThemeMode.system] follows the OS).
  /// Session-only; defaults to the OS setting so the app boots as before.
  AppThemeMode get themeMode => _themeMode;

  /// Fires when [themeMode] changes. Subscribe here (not the whole
  /// controller) for widgets that depend only on the appearance.
  ValueNotifier<AppThemeMode> get themeNotifier => _themeNotifier;
  final ValueNotifier<AppThemeMode> _themeNotifier =
      ValueNotifier<AppThemeMode>(AppThemeMode.system);

  set themeMode(AppThemeMode value) {
    if (value == _themeMode) return;
    _themeMode = value;
    _themeNotifier.value = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _themeNotifier.dispose();
    super.dispose();
  }
}
