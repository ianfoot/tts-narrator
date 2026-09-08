import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controller/app_controller.dart';
import '../editor/editor_screen.dart';
import '../menu/macos_menu.dart';
import '../narration/narration_screen.dart';
import '../theme/app_text_tokens.dart' show TextTokens;
import '../theme/app_tokens.dart';

/// Cross-platform app root: a [CupertinoApp] on macOS, a [MaterialApp]
/// elsewhere, sharing one [AppController] and navigator key.
///
/// Wires the controller's command slots: the native Open file picker and the
/// Narrate / Cancel slots (navigate to the run view; Cancel stops the run).
/// Preferences stays reserved for the native menu bar (Task 5).
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    widget.controller.onOpen = _openDocument;
    widget.controller.onNarrate = _startNarration;
    widget.controller.onCancel = () => widget.controller.cancelRun();
    widget.controller.onSetOutputFolder = widget.controller.pickOutputFolder;
    widget.controller.onToggleSettingsPanel =
        widget.controller.toggleSettingsPanel;
    widget.controller.saveLocationPicker = _pickSaveLocation;
    // Follow the system appearance live (CupertinoApp has no darkTheme/
    // themeMode, so the theme is rebuilt when the platform brightness flips).
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        _onPlatformBrightnessChanged;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        null;
    widget.controller.onOpen = null;
    widget.controller.onNarrate = null;
    widget.controller.onCancel = null;
    widget.controller.onSetOutputFolder = null;
    widget.controller.onToggleSettingsPanel = null;
    widget.controller.saveLocationPicker = null;
    super.dispose();
  }

  void _onPlatformBrightnessChanged() {
    if (mounted) setState(() {});
  }

  Future<String?> _pickSaveLocation() async {
    const group = XTypeGroup(label: TextTokens.app_fileTypeGroup, extensions: ['txt']);
    final location = await getSaveLocation(
      acceptedTypeGroups: const [group],
      suggestedName: widget.controller.documentName,
    );
    return location?.path;
  }

  /// Opens the native directory picker for the output destination; leaves the
  /// current directory unchanged when cancelled.
  Future<void> _openDocument() async {
    const group = XTypeGroup(label: TextTokens.app_fileTypeGroup, extensions: ['txt']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    try {
      widget.controller.loadFromFile(file.path);
    } on FileSystemException {
      // The picker only returns existing files; ignore races.
    }
  }

  void _startNarration() {
    if (widget.controller.narrateBlockReason() != null) return;
    // startRun sets _narrating synchronously, so a double-trigger cannot push
    // the run view twice (the second Narrate hits the re-entrancy guard).
    widget.controller.startRun();
    _navigatorKey.currentState?.push(_runRoute());
  }

  /// The run view's 250ms cross-fade slide-up from a 20px offset (UI spec §4).
  /// A bare [PageRouteBuilder] so macOS and Material present identically.
  PageRouteBuilder<void> _runRoute() {
    const duration = Duration(milliseconds: 250);
    final screenHeight = MediaQuery.sizeOf(
      _navigatorKey.currentContext ?? context,
    ).height;
    final beginDy = screenHeight > 0 ? 20 / screenHeight : 0.0;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          NarrationScreen(controller: widget.controller),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
          reverseCurve: Curves.easeInOut,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, beginDy),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: widget.controller.themeNotifier,
      builder: (context, themeMode, _) {
        final home = EditorScreen(controller: widget.controller);
        if (_isMac) {
          final dark =
              resolveBrightness(
                themeMode,
                WidgetsBinding.instance.platformDispatcher.platformBrightness,
              ) ==
              Brightness.dark;
          final palette = AppPalette.of(
            dark ? Brightness.dark : Brightness.light,
          );
          return CupertinoApp(
            title: TextTokens.app_title,
            navigatorKey: _navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: CupertinoThemeData(
              // Follows the system appearance (see the platformBrightness
              // listener).
              brightness: dark ? Brightness.dark : Brightness.light,
              primaryColor: palette.accentPrimary,
            ),
            // The native macOS menu bar lives above the editor route, so it
            // stays mounted (and functional) while the narration run view is
            // pushed on top. Home stays mounted under the pushed route.
            home: PlatformMenuBar(
              menus: buildMacMenu(
                controller: widget.controller,
                navigatorKey: _navigatorKey,
              ),
              child: home,
            ),
          );
        }
        final light = _materialTheme(Brightness.light);
        final dark = _materialTheme(Brightness.dark);
        return MaterialApp(
          title: TextTokens.app_title,
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: light,
          darkTheme: dark,
          themeMode: switch (themeMode) {
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
            AppThemeMode.system => ThemeMode.system,
          },
          home: home,
        );
      },
    );
  }

  /// Material [ThemeData] whose surfaces/text/accents map 1:1 onto the spec
  /// tokens, so the Material path renders the same palette as Cupertino.
  ThemeData _materialTheme(Brightness brightness) {
    final palette = AppPalette.of(brightness);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.m3Seed,
          brightness: brightness,
        ).copyWith(
          primary: palette.accentPrimary,
          onSurface: palette.textPrimary,
          onSurfaceVariant: palette.textSecondary,
          surface: palette.bgApp,
          surfaceContainerHighest: palette.bgSurfaceElevated,
          errorContainer: palette.accentError.withValues(alpha: 0.12),
          onErrorContainer: palette.accentError,
          outlineVariant: palette.borderSubtle,
        );
    return ThemeData(colorScheme: scheme);
  }
}
