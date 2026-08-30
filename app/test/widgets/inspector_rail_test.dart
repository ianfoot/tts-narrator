import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/settings/inspector_rail.dart';

void main() {
  late Directory dir;
  late String configPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_inspector_rail_');
    configPath = '${dir.path}/voice_config.json';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void writeConfig(Map<String, Object?> body) {
    File(configPath).writeAsStringSync(const JsonEncoder().convert(body));
  }

  AppController makeController() =>
      AppController(loader: VoiceConfigLoader(configPath: configPath));

  Future<void> pumpRail(WidgetTester tester, AppController controller) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InspectorRail(controller: controller)),
      ),
    );
  }

  group('defaults', () {
    testWidgets('boots with the fish model, its voice, and the defaults', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      expect(find.byKey(const Key('inspectorRail')), findsOneWidget);
      expect(find.byKey(const Key('modelDropdown')), findsOneWidget);
      expect(find.byKey(const Key('voiceDropdown')), findsOneWidget);
      expect(find.byKey(const Key('voiceRawField')), findsOneWidget);
      expect(find.byKey(const Key('accentField')), findsOneWidget);
      expect(find.byKey(const Key('styleField')), findsOneWidget);
      expect(find.byKey(const Key('prefixField')), findsOneWidget);
      expect(find.byKey(const Key('minWordsField')), findsOneWidget);
      expect(find.byKey(const Key('sampleLenField')), findsOneWidget);
      expect(find.byKey(const Key('outDirField')), findsOneWidget);
      expect(find.byKey(const Key('calmSwitch')), findsOneWidget);
      expect(find.byKey(const Key('resumeSwitch')), findsOneWidget);
      expect(find.byKey(const Key('railNarrateButton')), findsOneWidget);
      expect(find.byKey(const Key('railCloseButton')), findsOneWidget);

      final raw = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('voiceRawField')),
          matching: find.byType(TextField),
        ),
      );
      expect(raw.controller!.text, kDefaultProfile.voice);
    });
  });

  group('model & voice', () {
    const gemini = {
      'id': 'google/gemini-3.1-flash-tts-preview',
      'format': 'pcm',
      'sample_rate': 24000,
      'prompt_style': true,
    };

    testWidgets('switching the model resets the voice to its default', (
      tester,
    ) async {
      writeConfig({
        'models': {'gemini': gemini},
        'defaults': {'gemini': 'Charon'},
        'voices': {'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'}},
      });
      final c = makeController();
      await pumpRail(tester, c);

      await tester.tap(find.byKey(const Key('modelDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('google/gemini').last);
      await tester.pumpAndSettle();

      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'CN2pVME9cDEeMRXJzcMPYj0p');
      expect(c.voiceLabel, 'Charon');
      // The raw id field follows the new default.
      final raw = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('voiceRawField')),
          matching: find.byType(TextField),
        ),
      );
      expect(raw.controller!.text, 'CN2pVME9cDEeMRXJzcMPYj0p');
    });

    testWidgets('a user-set raw voice survives a model switch', (tester) async {
      writeConfig({
        'models': {'gemini': gemini},
        'defaults': {'gemini': 'Charon'},
        'voices': {'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'}},
      });
      final c = makeController();
      c.setVoice('my_custom_voice');
      await pumpRail(tester, c);

      await tester.tap(find.byKey(const Key('modelDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('google/gemini').last);
      await tester.pumpAndSettle();

      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'my_custom_voice');
    });

    testWidgets('picking a voice alias resolves to its raw id', (tester) async {
      writeConfig({
        'voices': {'fish': {'Narrator': 'hex123'}},
      });
      final c = makeController();
      await pumpRail(tester, c);

      await tester.tap(find.byKey(const Key('voiceDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Narrator').last);
      await tester.pumpAndSettle();

      expect(c.voice, 'hex123');
      expect(c.voiceLabel, 'Narrator');
    });

    testWidgets('typing a raw voice id updates the controller', (tester) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('voiceRawField')),
          matching: find.byType(TextField),
        ),
        'custom_raw_id',
      );
      await tester.pump();

      expect(c.voice, 'custom_raw_id');
      expect(c.voiceLabel, isNull);
    });
  });

  group('styling & run options', () {
    testWidgets('formatting fields write through to the controller', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('accentField')),
          matching: find.byType(TextField),
        ),
        'a calm brogue',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('styleField')),
          matching: find.byType(TextField),
        ),
        'measured, unhurried',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('prefixField')),
          matching: find.byType(TextField),
        ),
        'Read this passage.',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('outDirField')),
          matching: find.byType(TextField),
        ),
        'audio/output',
      );
      await tester.pump();

      expect(c.accent, 'a calm brogue');
      expect(c.style, 'measured, unhurried');
      expect(c.passagePrefix, 'Read this passage.');
      expect(c.outDir, 'audio/output');
    });

    testWidgets('number fields set min words and sample length', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('minWordsField')),
          matching: find.byType(TextField),
        ),
        '50',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('sampleLenField')),
          matching: find.byType(TextField),
        ),
        '3',
      );
      await tester.pump();

      expect(c.minWords, 50);
      expect(c.sampleLen, 3);

      // Clearing sample length makes it optional again.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('sampleLenField')),
          matching: find.byType(TextField),
        ),
        '',
      );
      await tester.pump();
      expect(c.sampleLen, isNull);
    });

    testWidgets('min words clamps to a positive value', (tester) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('minWordsField')),
          matching: find.byType(TextField),
        ),
        '0',
      );
      await tester.pump();

      expect(c.minWords, 1);
    });

    testWidgets('calm and resume switches toggle their flags', (tester) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      await tester.tap(find.byKey(const Key('calmSwitch')));
      await tester.tap(find.byKey(const Key('resumeSwitch')));
      await tester.pump();

      expect(c.useCalmTag, isTrue);
      expect(c.resume, isTrue);
    });
  });

  group('narrate', () {
    testWidgets('dispatches through the Narrate slot when text is present', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController()..setText('Enough words to narrate.');
      var narrated = false;
      c.onNarrate = () => narrated = true;
      await pumpRail(tester, c);

      await tester.tap(find.byKey(const Key('railNarrateButton')));
      await tester.pump();

      expect(narrated, isTrue);
      expect(find.byKey(const Key('railGuard')), findsNothing);
    });

    testWidgets('shows the guard banner on empty text and does not dispatch', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      var narrated = false;
      c.onNarrate = () => narrated = true;
      await pumpRail(tester, c);

      await tester.tap(find.byKey(const Key('railNarrateButton')));
      await tester.pump();

      expect(narrated, isFalse);
      expect(find.byKey(const Key('railGuard')), findsOneWidget);
      expect(find.textContaining('Nothing to narrate yet'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('railGuard')), findsNothing);
    });
  });

  group('cupertino (macOS)', () {
    testWidgets('renders and switches models without Material errors', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      writeConfig({
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
            'prompt_style': true,
          },
        },
        'defaults': {'gemini': 'Charon'},
        'voices': {'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'}},
      });
      final c = makeController();
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CupertinoApp(home: InspectorRail(controller: c)),
      );

      expect(find.byKey(const Key('inspectorRail')), findsOneWidget);
      expect(find.byKey(const Key('modelDropdown')), findsOneWidget);
      expect(find.byKey(const Key('calmSwitch')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Open the native pop-up menu and pick gemini.
      await tester.tap(find.byKey(const Key('modelDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('google/gemini').last);
      await tester.pumpAndSettle();

      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'CN2pVME9cDEeMRXJzcMPYj0p');
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('close', () {
    testWidgets('the close button reports hide to its caller', (tester) async {
      writeConfig({});
      final c = makeController();
      var closed = false;
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectorRail(controller: c, onClose: () => closed = true),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('railCloseButton')));
      await tester.pump();

      expect(closed, isTrue);
    });
  });
}