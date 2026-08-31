import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../controller/app_controller.dart';
import '../editor/editor_screen.dart';
import '../menu/macos_menu.dart';
import '../narration/narration_screen.dart';

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
  }

  @override
  void dispose() {
    widget.controller.onOpen = null;
    widget.controller.onNarrate = null;
    widget.controller.onCancel = null;
    super.dispose();
  }

  Future<void> _openDocument() async {
    const group = XTypeGroup(label: 'Text', extensions: ['txt']);
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
    final route = _isMac
        ? CupertinoPageRoute<void>(
            builder: (_) => NarrationScreen(controller: widget.controller))
        : MaterialPageRoute<void>(
            builder: (_) => NarrationScreen(controller: widget.controller));
    _navigatorKey.currentState?.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final home = EditorScreen(controller: widget.controller);
    if (_isMac) {
      return CupertinoApp(
        title: 'TTS Narrator',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(brightness: Brightness.light),
        // The native macOS menu bar lives above the editor route, so it stays
        // mounted (and functional) while the narration run view is pushed on
        // top. Home stays mounted under the pushed route.
        home: PlatformMenuBar(
          menus: buildMacMenu(
            controller: widget.controller,
            navigatorKey: _navigatorKey,
          ),
          child: home,
        ),
      );
    }
    return MaterialApp(
      title: 'TTS Narrator',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF5E5336),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF5E5336),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: home,
    );
  }
}