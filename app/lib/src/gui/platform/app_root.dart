import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../controller/app_controller.dart';
import '../editor/editor_screen.dart';
import '../menu/macos_menu.dart';
import '../narration/narration_screen.dart';
import '../theme/app_text_tokens.dart' show TextTokens;
import '../theme/app_tokens.dart';
import 'platform_detection.dart';

/// Cross-platform app root: a single [CupertinoApp] shell that mounts the
/// native menu bar on macOS (whose items carry their own ⌘ shortcuts) and a
/// [CallbackShortcuts] accelerator map on Linux/Windows, all dispatching
/// through one [AppController] and navigator key.
///
/// Wires the controller's command slots: the native Open file picker and the
/// Narrate / Cancel slots (navigate to the run view; Cancel stops the run).
/// Preferences stays reserved for the native menu bar.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    widget.controller.commands.onOpen = _openDocument;
    widget.controller.commands.onNarrate = _startNarration;
    widget.controller.commands.onCancel = () => widget.controller.cancelRun();
    widget.controller.commands.onSetOutputFolder =
        widget.controller.pickOutputFolder;
    widget.controller.commands.onToggleSettingsPanel =
        widget.controller.toggleSettingsPanel;
    widget.controller.commands.onClearText = widget.controller.clearText;
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
    widget.controller.commands.onOpen = null;
    widget.controller.commands.onNarrate = null;
    widget.controller.commands.onCancel = null;
    widget.controller.commands.onSetOutputFolder = null;
    widget.controller.commands.onToggleSettingsPanel = null;
    widget.controller.commands.onClearText = null;
    widget.controller.saveLocationPicker = null;
    super.dispose();
  }

  void _onPlatformBrightnessChanged() {
    if (mounted) setState(() {});
  }

  Future<String?> _pickSaveLocation() async {
    const group = XTypeGroup(
      label: TextTokens.app_fileTypeGroup,
      extensions: ['txt'],
    );
    final location = await getSaveLocation(
      acceptedTypeGroups: const [group],
      suggestedName: widget.controller.documentName,
    );
    return location?.path;
  }

  /// Opens the native directory picker for the output destination; leaves the
  /// current directory unchanged when cancelled.
  Future<void> _openDocument() async {
    const group = XTypeGroup(
      label: TextTokens.app_fileTypeGroup,
      extensions: ['txt'],
    );
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
  /// A bare [PageRouteBuilder] so the run view presents identically on every
  /// platform.
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
        final dark =
            resolveBrightness(
              themeMode,
              WidgetsBinding.instance.platformDispatcher.platformBrightness,
            ) ==
            Brightness.dark;
        final palette = AppPalette.of(
          dark ? Brightness.dark : Brightness.light,
        );
        final editor = EditorScreen(controller: widget.controller);
        final Widget home;
        if (isMac) {
          // The native macOS menu bar lives above the editor route, so it
          // stays mounted (and functional) while the narration run view is
          // pushed on top. Home stays mounted under the pushed route.
          home = PlatformMenuBar(
            menus: buildMacMenu(
              controller: widget.controller,
              navigatorKey: _navigatorKey,
            ),
            child: editor,
          );
        } else {
          // Keyboard accelerators for the platforms without a native menu bar;
          // they drive the same command slots the macOS menu binds.
          home = CallbackShortcuts(
            bindings: _desktopShortcuts(),
            child: editor,
          );
        }
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
          home: home,
        );
      },
    );
  }

  /// Ctrl/Shift accelerators for Linux/Windows, mirroring the macOS menu items
  /// and their guards: Open, Output Folder, Narrate, Clear, Save, Save As,
  /// Toggle Settings Panel and Close.
  Map<ShortcutActivator, VoidCallback> _desktopShortcuts() {
    final controller = widget.controller;
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
          controller.commands.onOpen?.call(),
      const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
          controller.commands.onSetOutputFolder?.call(),
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
        if (controller.narrateBlockReason() != null) return;
        controller.commands.onNarrate?.call();
      },
      const SingleActivator(
        LogicalKeyboardKey.keyL,
        control: true,
        shift: true,
      ): () {
        if (!controller.canClearText) return;
        controller.clearText();
      },
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          controller.save(),
      const SingleActivator(
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
      ): () =>
          controller.saveAs(),
      const SingleActivator(LogicalKeyboardKey.backslash, control: true): () =>
          controller.commands.onToggleSettingsPanel?.call(),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
          _navigatorKey.currentState?.maybePop(),
    };
  }
}
