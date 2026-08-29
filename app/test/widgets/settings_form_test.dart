import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'package:tts_narrator/src/gui/run_screen.dart';
import 'package:tts_narrator/src/gui/settings_form.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_gui_test_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> useBigSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  String writeInput() {
    final f = File('${dir.path}/story.txt')
      ..writeAsStringSync('Hello world. This is a short sentence '
          'for the narration test.');
    return f.path;
  }

  Future<void> writeConfig(Map<String, Object?> body) async {
    File('${dir.path}/voice_config.json')
        .writeAsStringSync(const JsonEncoder().convert(body));
  }

  testWidgets('renders and routes to the run screen with a valid config', (
    tester,
  ) async {
    await useBigSurface(tester);
    final input = writeInput();
    await writeConfig({
      'api_key': 'sk-test',
      'voices': {
        'fish': {'Narrator': 'hex123'},
      },
    });

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(configPath: '${dir.path}/voice_config.json')),
    );
    await tester.enterText(find.byKey(const Key('inputPathField')), input);
    await tester.ensureVisible(find.byKey(const Key('narrateButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('narrateButton')));
    await tester.pumpAndSettle();

    final run = tester.widget<RunScreen>(find.byType(RunScreen));
    expect(run.config.inputPath, input);
    expect(run.config.profile.alias, 'gemini');
    expect(run.config.voice, kGeminiProfile.defaultVoice);
    expect(run.config.apiKey, 'sk-test'); // loaded from config, not env
  });

  testWidgets('selecting a voice alias fills the raw id field', (tester) async {
    await useBigSurface(tester);
    await writeConfig({
      'voices': {
        'fish': {'Narrator': 'hex123'},
      },
    });

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(configPath: '${dir.path}/voice_config.json')),
    );

    // Switch to fish: voice resets to the fish default.
    await tester.tap(find.byKey(const Key('modelDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('fish — fish-audio/s2.1-pro-free').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(
      find.byKey(const Key('voiceRawField')),
    ).controller!.text, kFishProfile.defaultVoice);

    // Select the alias from the voice dropdown -> raw field fills with hex123.
    await tester.tap(find.byKey(const Key('voiceDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Narrator (alias)').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(
      find.byKey(const Key('voiceRawField')),
    ).controller!.text, 'hex123');
  });

  testWidgets('typing a raw voice id passes through untouched', (tester) async {
    await useBigSurface(tester);
    final input = writeInput();
    await writeConfig({});

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(configPath: '${dir.path}/voice_config.json')),
    );

    // fish is free-form, so any raw id is accepted as-is.
    await tester.tap(find.byKey(const Key('modelDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('fish — fish-audio/s2.1-pro-free').last);
    await tester.pumpAndSettle();

    const raw = '2fd511bd06904a21a971c6551dfb853a';
    await tester.enterText(find.byKey(const Key('voiceRawField')), raw);
    await tester.enterText(find.byKey(const Key('inputPathField')), input);
    await tester.ensureVisible(find.byKey(const Key('narrateButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('narrateButton')));
    await tester.pumpAndSettle();

    final run = tester.widget<RunScreen>(find.byType(RunScreen));
    expect(run.config.voice, raw);
    expect(run.config.profile.alias, 'fish');
  });
}