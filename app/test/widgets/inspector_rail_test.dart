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
import '../support/fake_tts_provider.dart';

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_inspector_rail_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Writes the shared grouped config body onto the flat layout: global keys
  /// to config.json, and each `models` entry plus its `defaults`/`pricing`/
  /// `voices` to <alias>.json.
  void writeConfig(Map<String, Object?> body) {
    final global = <String, Object?>{
      if (body['default_provider'] != null)
        'default_provider': body['default_provider'],
      if (body['providers'] != null) 'providers': body['providers'],
    };
    File('$configDir/config.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder().convert(global));

    final models = (body['models'] as Map<String, Object?>?) ?? {};
    if (models.isEmpty) return;
    final defaults = (body['defaults'] as Map<String, Object?>?) ?? {};
    final pricing = (body['pricing'] as Map<String, Object?>?) ?? {};
    final voices = (body['voices'] as Map<String, Object?>?) ?? {};
    Directory(configDir).createSync(recursive: true);
    models.forEach((alias, spec) {
      final m = Map<String, Object?>.from(spec as Map<String, Object?>);
      final dv = defaults[alias];
      final pr = pricing[alias];
      final vo = voices[alias];
      if (dv is String) m['default_voice'] = dv;
      if (pr is Map) m['pricing'] = pr;
      if (vo is Map) m['voices'] = vo;
      File('$configDir/$alias.json')
          .writeAsStringSync(const JsonEncoder().convert(m));
    });
  }

  AppController makeController() =>
      AppController(loader: VoiceConfigLoader(configDir: configDir));

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
      expect(find.byKey(const Key('minWordsField')), findsOneWidget);
      expect(find.byKey(const Key('sampleLenField')), findsOneWidget);
      expect(find.byKey(const Key('outDirField')), findsOneWidget);
      expect(find.byKey(const Key('resumeSwitch')), findsOneWidget);
      expect(find.byKey(const Key('railNarrateButton')), findsOneWidget);
      expect(find.byKey(const Key('railCloseButton')), findsOneWidget);
      // The default fish model's plugin declares no model options, so no
      // styling-only controls (the gemini-only ones) render for it.
      expect(find.text('MODEL OPTIONS'), findsNothing);
      expect(find.byKey(const Key('accentField')), findsNothing);
      expect(find.byKey(const Key('styleField')), findsNothing);
      expect(find.byKey(const Key('passagePrefixField')), findsNothing);
      expect(find.byKey(const Key('useCalmTagSwitch')), findsNothing);

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
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free', 'format': 'mp3'},
        },
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

  group('model options (from the plugin spec)', () {
    const geminiSpec = ModelUiSpec([
      ModelUiOption(key: 'accent', label: 'Accent'),
      ModelUiOption(key: 'style', label: 'Style / register'),
      ModelUiOption(
        key: 'passagePrefix',
        label: 'Passage prefix',
        type: ModelUiOptionType.multiline,
      ),
      ModelUiOption(
        key: 'useCalmTag',
        label: 'Prepend [calm] tag',
        type: ModelUiOptionType.bool,
      ),
    ]);

    testWidgets('declared fields render and write through to the controller', (
      tester,
    ) async {
      writeConfig({});
      final fake = FakeTtsProvider()..modelUiSpec = geminiSpec;
      fake.register();
      final c = makeController();
      await pumpRail(tester, c);

      // The plugin declared the section, so the controls exist.
      expect(find.text('MODEL OPTIONS'), findsOneWidget);
      expect(find.byKey(const Key('accentField')), findsOneWidget);
      expect(find.byKey(const Key('styleField')), findsOneWidget);
      expect(find.byKey(const Key('passagePrefixField')), findsOneWidget);
      expect(find.byKey(const Key('useCalmTagSwitch')), findsOneWidget);

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
          of: find.byKey(const Key('passagePrefixField')),
          matching: find.byType(TextField),
        ),
        'Read this passage.',
      );
      await tester.tap(find.byKey(const Key('useCalmTagSwitch')));
      await tester.pump();

      expect(c.accent, 'a calm brogue');
      expect(c.style, 'measured, unhurried');
      expect(c.passagePrefix, 'Read this passage.');
      expect(c.useCalmTag, isTrue);
    });

    testWidgets('an empty spec renders no model options section', (
      tester,
    ) async {
      writeConfig({});
      FakeTtsProvider().register();
      final c = makeController();
      await pumpRail(tester, c);

      expect(find.text('MODEL OPTIONS'), findsNothing);
      expect(find.byKey(const Key('accentField')), findsNothing);
      expect(find.byKey(const Key('useCalmTagSwitch')), findsNothing);
    });

    testWidgets('unbindable keys are ignored rather than crashing the rail', (
      tester,
    ) async {
      writeConfig({});
      // A future plugin may declare a key this app version cannot bind; it must
      // not render and must not throw during build.
      final fake = FakeTtsProvider()
        ..modelUiSpec = const ModelUiSpec([
          ModelUiOption(key: 'speed', label: 'Speaking rate'),
          ModelUiOption(key: 'accent', label: 'Accent'),
        ]);
      fake.register();
      final c = makeController();
      await pumpRail(tester, c);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('speedField')), findsNothing);
      expect(find.byKey(const Key('accentField')), findsOneWidget);
    });

    testWidgets('a declared hint shows as the field placeholder', (
      tester,
    ) async {
      writeConfig({});
      final fake = FakeTtsProvider()
        ..modelUiSpec = const ModelUiSpec([
          ModelUiOption(
            key: 'style',
            label: 'Style / register',
            hint: 'e.g. warm, restrained',
          ),
        ]);
      fake.register();
      final c = makeController();
      await pumpRail(tester, c);

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('styleField')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.decoration?.hintText, 'e.g. warm, restrained');
    });
  });

  group('run options', () {
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

    testWidgets('the output directory and resume switch write through', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('outDirField')),
          matching: find.byType(TextField),
        ),
        'audio/output',
      );
      await tester.tap(find.byKey(const Key('resumeSwitch')));
      await tester.pump();

      expect(c.outDir, 'audio/output');
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
      // The fake stands in for the openrouter plugin: gemini declares its
      // styling options; the default fish model declares none.
      final fake = FakeTtsProvider()
        ..specsByAlias['gemini'] = const ModelUiSpec([
          ModelUiOption(key: 'accent', label: 'Accent'),
          ModelUiOption(key: 'style', label: 'Style / register'),
          ModelUiOption(
            key: 'passagePrefix',
            label: 'Passage prefix',
            type: ModelUiOptionType.multiline,
          ),
          ModelUiOption(
            key: 'useCalmTag',
            label: 'Prepend [calm] tag',
            type: ModelUiOptionType.bool,
          ),
        ]);
      fake.register();
      final c = makeController();
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CupertinoApp(home: InspectorRail(controller: c)),
      );

      expect(find.byKey(const Key('inspectorRail')), findsOneWidget);
      expect(find.byKey(const Key('modelDropdown')), findsOneWidget);
      // The default fish model declares no options -> no styling-only controls.
      expect(find.byKey(const Key('useCalmTagSwitch')), findsNothing);
      expect(tester.takeException(), isNull);

      // Open the native pop-up menu and pick gemini.
      await tester.tap(find.byKey(const Key('modelDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('google/gemini').last);
      await tester.pumpAndSettle();

      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'CN2pVME9cDEeMRXJzcMPYj0p');
      // Switching to gemini brings its plugin-declared options.
      expect(find.byKey(const Key('accentField')), findsOneWidget);
      expect(find.byKey(const Key('useCalmTagSwitch')), findsOneWidget);
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