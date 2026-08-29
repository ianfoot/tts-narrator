import 'package:flutter/material.dart';

import 'settings_form.dart';

/// Root widget for the TTS Narrator desktop app.
class TtsNarratorApp extends StatelessWidget {
  const TtsNarratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TTS Narrator',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF5E5336),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF5E5336),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const SettingsScreen(),
    );
  }
}