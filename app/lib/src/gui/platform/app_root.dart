import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../settings/settings_screen.dart';
import '../controller/app_controller.dart';
import '../controller/document_controller.dart' show untitledDocumentName;
import '../editor/editor_screen.dart';
import '../menu/linux_menu_bar.dart';
import '../menu/macos_menu.dart';
import '../menu/quit_app.dart';
import '../narration/narration_screen.dart';
import '../../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import 'platform_detection.dart';

/// Cross-platform app root: a single [CupertinoApp] shell that mounts the
/// native menu bar on macOS (whose items carry their own ⌘ shortcuts) and an
/// in-app [LinuxMenuBar] plus a [CallbackShortcuts] accelerator map on
/// Linux/Windows, all dispatching through one [AppController] and navigator key.
///
/// Wires the controller's command slots: the native Open file picker, the
/// Narrate / Cancel slots (navigate to the run view; Cancel stops the run) and
/// Settings (push the providers & voices screen). Every pushed full-screen route
/// goes through [_fadeSlideRoute] so the two present as one family.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// Set while the settings screen is on the navigator stack, so a repeated
  /// ⌘, cannot stack two copies. Cleared on the route's pop.
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.commands.onOpen = _openDocument;
    widget.controller.commands.onNarrate = _startNarration;
    widget.controller.commands.onCancel = () => widget.controller.cancelRun();
    widget.controller.commands.onSetOutputFolder =
        widget.controller.pickOutputFolder;
    widget.controller.commands.onToggleRunSetupPanel =
        widget.controller.toggleRunSetupPanel;
    widget.controller.commands.onClearText = widget.controller.clearText;
    widget.controller.commands.onSettings = _openSettings;
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
    widget.controller.commands.onToggleRunSetupPanel = null;
    widget.controller.commands.onClearText = null;
    widget.controller.commands.onSettings = null;
    widget.controller.saveLocationPicker = null;
    super.dispose();
  }

  void _onPlatformBrightnessChanged() {
    if (mounted) setState(() {});
  }

  Future<String?> _pickSaveLocation() async {
    final l10n = AppLocalizations.of(context);
    final group = XTypeGroup(
      label: l10n.app_fileTypeGroup,
      extensions: ['txt'],
    );
    final location = await getSaveLocation(
      acceptedTypeGroups: [group],
      suggestedName: widget.controller.documentName ?? untitledDocumentName,
    );
    return location?.path;
  }

  /// Opens the native directory picker for the output destination; leaves the
  /// current directory unchanged when cancelled.
  Future<void> _openDocument() async {
    final l10n = AppLocalizations.of(context);
    final group = XTypeGroup(
      label: l10n.app_fileTypeGroup,
      extensions: ['txt'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
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

  /// Opens the providers & voices settings screen. Guarded against a
  /// double-trigger the same way [narrateBlockReason] guards the run view: the
  /// slot is a plain callback, so a second ⌘, before the first push settles
  /// would stack two copies of the screen.
  void _openSettings() {
    if (_settingsOpen) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _settingsOpen = true;
    // Cleared on the way back and on the way out if the push never completes,
    // so a navigator that goes away mid-flight cannot latch the guard.
    navigator
        .push(
          _fadeSlideRoute(
            (context) => SettingsScreen(controller: widget.controller),
          ),
        )
        .then((_) => _settingsOpen = false)
        .onError((_, _) => _settingsOpen = false);
  }

  /// The run view's 250ms cross-fade slide-up from a 20px offset (UI spec §4).
  /// A bare [PageRouteBuilder] so the run view presents identically on every
  /// platform.
  PageRouteBuilder<void> _runRoute() => _fadeSlideRoute(
    (context) => NarrationScreen(controller: widget.controller),
  );

  /// The shared full-screen push: a 250ms fade-and-slide from 20px below, so the
  /// narration run view and the settings screen present as one family rather
  /// than as two unrelated routes.
  PageRouteBuilder<void> _fadeSlideRoute(WidgetBuilder builder) {
    const duration = Duration(milliseconds: 250);
    final screenHeight = MediaQuery.sizeOf(
      _navigatorKey.currentContext ?? context,
    ).height;
    final beginDy = screenHeight > 0 ? 20 / screenHeight : 0.0;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
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
        final TransitionBuilder? acceleratorHost;
        if (isMac) {
          // The native macOS menu bar lives above the editor route, so it
          // stays mounted (and functional) while the narration run view is pushed
          // on top.
          home = PlatformMenuBar(
            menus: buildMacMenu(
              controller: widget.controller,
              navigatorKey: _navigatorKey,
              l10n: AppLocalizations.of(context),
            ),
            child: editor,
          );
          acceleratorHost = null;
        } else {
          // Keyboard accelerators for the platforms without a native menu bar;
          // they drive the same command slots the macOS menu binds. Mounted
          // above the Navigator so pushed routes keep them.
          home = LinuxMenuBar(
            controller: widget.controller,
            navigatorKey: _navigatorKey,
            child: editor,
          );
          acceleratorHost = (context, child) => CallbackShortcuts(
            bindings: _desktopShortcuts(),
            child: child ?? const SizedBox.shrink(),
          );
        }
        return CupertinoApp(
          title: AppLocalizations.of(context).app_title,
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          // Deliberately NOT AppLocalizations.localizationsDelegates: that
          // bundle pulls in GlobalMaterialLocalizations, which would resolve
          // framework strings for the Material widgets in the shared widget
          // layer. The menu bar relies on staying Material-free (see
          // LinuxMenuBar's class doc), so adding Material localization is a
          // deliberate, separately-audited change.
          localizationsDelegates: const [
            AppLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
            DefaultCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: widget.controller.locale,
          builder: acceleratorHost,
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
  /// Toggle Settings Panel and Quit.
  ///
  /// Accelerators that would alter the document or start a run are deliberately
  /// absent: those live on the in-app menu bar's buttons, which Flutter keeps
  /// focused while a submenu is open, so the menu's own key handling wins over
  /// these bindings instead of both firing.
  Map<ShortcutActivator, VoidCallback> _desktopShortcuts() {
    final controller = widget.controller;
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.backslash, control: true): () =>
          controller.commands.onToggleRunSetupPanel?.call(),
      const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
          controller.commands.onSettings?.call(),
      const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () =>
          quitApp(),
    };
  }
}
