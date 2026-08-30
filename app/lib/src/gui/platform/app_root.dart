import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../controller/app_controller.dart';
import '../editor/editor_screen.dart';

/// Cross-platform app root: a [CupertinoApp] on macOS, a [MaterialApp]
/// elsewhere, sharing one [AppController] and navigator key.
///
/// Wires the controller's command slots that are shared across platforms: the
/// native Open file picker. The Narrate slot gains the narration run view in a
/// later task; Cancel / Preferences are reserved for the run view and the
/// native menu bar.
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
  }

  @override
  void dispose() {
    widget.controller.onOpen = null;
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

  @override
  Widget build(BuildContext context) {
    final home = EditorScreen(controller: widget.controller);
    if (_isMac) {
      return CupertinoApp(
        title: 'TTS Narrator',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(brightness: Brightness.light),
        home: home,
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