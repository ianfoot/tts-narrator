import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/settings/settings_panel.dart';
import 'package:tts_narrator/src/gui/platform/widgets/platform_segmented.dart';

import '../support/fake_tts_provider.dart';

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_settings_panel_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Writes the shared grouped config body onto the flat layout: global keys
  /// (`default_model`, `providers`) to config.json, and each `models` entry
  /// plus its `defaults`/`pricing`/`voices` to <alias>.json. Specs without a
  /// `provider` default to `openrouter` so model files stay valid.
  void writeConfig(Map<String, Object?> body) {
    final global = <String, Object?>{
      if (body['default_model'] != null) 'default_model': body['default_model'],
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
      m.putIfAbsent('provider', () => 'openrouter');
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
        home: Scaffold(body: SettingsPanel(controller: controller)),
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

      expect(find.byKey(const Key('settingsPanel')), findsOneWidget);
      expect(find.byKey(const Key('modelDropdown')), findsOneWidget);
      expect(find.byKey(const Key('voiceDropdown')), findsOneWidget);
      expect(find.byKey(const Key('voiceAdvancedDisclosure')), findsOneWidget);
      // The advanced voice id is collapsed by default.
      expect(find.byKey(const Key('voiceRawField')), findsNothing);
      expect(find.text('Overrides selected alias'), findsOneWidget);
      expect(find.byKey(const Key('minWordsSlider')), findsOneWidget);
      expect(find.byKey(const Key('minWordsBadge')), findsOneWidget);
      expect(find.byKey(const Key('sampleSwitch')), findsOneWidget);
      expect(find.byKey(const Key('resumeSwitch')), findsOneWidget);
      // The default fish model's plugin declares no model options, so no
      // styling-only controls (the gemini-only ones) render for it.
      expect(find.text('MODEL OPTIONS'), findsNothing);
      expect(find.byKey(const Key('accentField')), findsNothing);
      expect(find.byKey(const Key('styleField')), findsNothing);
      expect(find.byKey(const Key('passagePrefixField')), findsNothing);
      expect(find.byKey(const Key('useCalmTagSwitch')), findsNothing);

      // The min-words badge reflects the controller default.
      expect(
        find.descendant(
          of: find.byKey(const Key('minWordsBadge')),
          matching: find.text('30'),
        ),
        findsOneWidget,
      );
    });
  });

  /// Expands the collapsed "Advanced Voice ID" disclosure.
  Future<void> expandVoiceRaw(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('voiceAdvancedDisclosure')));
    await tester.pump();
  }

  group('model & voice', () {
    const gemini = {
      'id': 'google/gemini-3.1-flash-tts-preview',
      'format': 'pcm',
      'sample_rate': 24000,
      'prompt_style': true,
      'display_name': 'Gemini 3.1 Flash TTS',
    };

    testWidgets('switching the model resets the voice to its default', (
      tester,
    ) async {
      writeConfig({
        'models': {'gemini': gemini},
        'defaults': {'gemini': 'Charon'},
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
        },
      });
      final c = makeController();
      await pumpRail(tester, c);
      await expandVoiceRaw(tester);

      await tester.tap(find.byKey(const Key('modelDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Gemini 3.1').last);
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
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
        },
      });
      final c = makeController();
      c.setVoice('my_custom_voice');
      await pumpRail(tester, c);

      await tester.tap(find.byKey(const Key('modelDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Gemini 3.1').last);
      await tester.pumpAndSettle();

      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'my_custom_voice');
    });

    testWidgets('picking a voice alias resolves to its raw id', (tester) async {
      writeConfig({
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free', 'format': 'mp3'},
        },
        'voices': {
          'fish': {'Narrator': 'hex123'},
        },
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
      await expandVoiceRaw(tester);

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

    testWidgets('the advanced voice id disclosure reveals the raw field', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      expect(find.byKey(const Key('voiceRawField')), findsNothing);
      expect(find.text('Overrides selected alias'), findsOneWidget);

      await expandVoiceRaw(tester);

      expect(find.byKey(const Key('voiceRawField')), findsOneWidget);
      expect(find.text('Overrides selected alias'), findsNothing);

      await tester.tap(find.text('Advanced Voice ID'));
      await tester.pump();
      expect(find.byKey(const Key('voiceRawField')), findsNothing);
    });

    testWidgets('gender control narrows the voice list for tagged models', (
      tester,
    ) async {
      writeConfig({
        'models': {
          'kokoro': {'id': 'hexgrad/kokoro-82m', 'format': 'mp3'},
        },
        'defaults': {'kokoro': 'Emma'},
        'voices': {
          'kokoro': {
            'Alice': {'id': 'bf_alice', 'gender': 'female'},
            'Daniel': {'id': 'bm_daniel', 'gender': 'male'},
            'Emma': {'id': 'bf_emma', 'gender': 'female'},
            'Fable': {'id': 'bm_fable', 'gender': 'male'},
          },
        },
      });
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = makeController();
      c.changeModel('kokoro');
      await pumpRail(tester, c);

      final control = tester.widget<PlatformSegmentedControl<VoiceGender?>>(
        find.byKey(const Key('genderControl')),
      );
      expect(control.value, isNull);
      expect(control.items.map((it) => it.$2), ['Any', 'Female', 'Male']);

      // Female voices get a compact shorthand in the dropdown.
      await tester.tap(find.byKey(const Key('voiceDropdown')));
      await tester.pumpAndSettle();
      expect(find.text('Emma (f)').last, findsOneWidget);
      expect(find.text('Alice (f)').last, findsOneWidget);
      // Close the open dropdown.
      await tester.tapAt(const Offset(600, 100));
      await tester.pumpAndSettle();

      // Switch to Male: the filter narrows the picker and auto-selects.
      await tester.tap(find.text('Male'));
      await tester.pump();
      expect(c.voiceGenderFilter, VoiceGender.male);
      expect(c.voiceLabel, 'Daniel');

      await tester.tap(find.byKey(const Key('voiceDropdown')));
      await tester.pumpAndSettle();
      expect(find.text('Daniel (m)').last, findsOneWidget);
      expect(find.text('Fable (m)').last, findsOneWidget);
      expect(find.text('Emma (f)'), findsNothing);

      // Back to Any: the picker returns to the full list (Material path must
      // forward the null selection instead of treating it as no-op).
      await tester.tapAt(const Offset(600, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any'));
      await tester.pump();
      expect(c.voiceGenderFilter, isNull);
      await tester.tap(find.byKey(const Key('voiceDropdown')));
      await tester.pumpAndSettle();
      expect(find.text('Emma (f)').last, findsOneWidget);
      expect(find.text('Daniel (m)').last, findsOneWidget);
    });

    testWidgets('gemini shows no voice-picker gender control without tags', (
      tester,
    ) async {
      writeConfig({
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
            'prompt_style': true,
            'display_name': 'Gemini 3.1 Flash TTS',
          },
        },
        'defaults': {'gemini': 'Charon'},
        'voices': {
          'gemini': {'Charon': 'Charon'},
        },
      });
      // The real openrouter plugin surfaces gender as a Model option for
      // prompt-styled models; emulate that spec via the fake provider.
      final fake = FakeTtsProvider()
        ..modelUiSpec = const ModelUiSpec([
          ModelUiOption(
            key: 'gender',
            label: 'Narrator gender',
            type: ModelUiOptionType.gender,
          ),
        ]);
      fake.register();
      final c = makeController();
      c.changeModel('gemini');
      await pumpRail(tester, c);

      // Untagged voices -> no filter in "Model & voice".
      expect(find.byKey(const Key('genderControl')), findsNothing);
      // The plugin instead surfaces the option in Model options.
      expect(find.byKey(const Key('genderOptionSegmented')), findsOneWidget);
      expect(find.text('Narrator gender'), findsOneWidget);

      // Tapping Male drives the controller's narrator gender (and its prompt
      // rewrite) for the prompt-styled model.
      await tester.tap(find.text('Male'));
      await tester.pump();
      expect(c.voiceGenderFilter, VoiceGender.male);
      expect(c.passagePrefix, contains('male narrator'));
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
    testWidgets('the whole-file switch renders on by default off', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      expect(c.sendWholeFile, isFalse);
      expect(find.byKey(const Key('wholeFileSwitch')), findsOneWidget);
      // Segmentation controls are visible while the switch is off.
      expect(find.byKey(const Key('minWordsSlider')), findsOneWidget);
      expect(find.byKey(const Key('minWordsBadge')), findsOneWidget);
    });

    testWidgets('enabling whole-file hides the min-words section', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      await tester.tap(find.byKey(const Key('wholeFileSwitch')));
      await tester.pump();

      expect(c.sendWholeFile, isTrue);
      expect(find.byKey(const Key('minWordsSlider')), findsNothing);
      expect(find.byKey(const Key('minWordsBadge')), findsNothing);
      expect(find.byKey(const Key('sampleSwitch')), findsOneWidget);
      expect(find.byKey(const Key('resumeSwitch')), findsOneWidget);

      // Toggling back restores the slider with the preserved value.
      await tester.tap(find.byKey(const Key('wholeFileSwitch')));
      await tester.pump();
      expect(c.sendWholeFile, isFalse);
      expect(find.byKey(const Key('minWordsSlider')), findsOneWidget);
      expect(find.byKey(const Key('minWordsBadge')), findsOneWidget);
    });

    testWidgets('the min-words slider updates the controller within 10-100', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      expect(c.minWords, 30);
      // Drag to the far right -> 100.
      await tester.drag(
        find.byKey(const Key('minWordsSlider')),
        const Offset(600, 0),
      );
      await tester.pump();
      expect(c.minWords, 100);

      // Drag to the far left -> 10 (the slider's minimum).
      await tester.drag(
        find.byKey(const Key('minWordsSlider')),
        const Offset(-600, 0),
      );
      await tester.pump();
      expect(c.minWords, 10);
    });

    testWidgets('sample mode toggles the inline segment count input', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      expect(find.byKey(const Key('sampleLenField')), findsNothing);

      await tester.tap(find.byKey(const Key('sampleSwitch')));
      await tester.pump();
      expect(c.sampleLen, 1);
      expect(find.byKey(const Key('sampleLenField')), findsOneWidget);
      expect(find.text('Narrate first segments only'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('sampleLenField')),
          matching: find.byType(TextField),
        ),
        '3',
      );
      await tester.pump();
      expect(c.sampleLen, 3);

      await tester.tap(find.byKey(const Key('sampleSwitch')));
      await tester.pump();
      expect(c.sampleLen, isNull);
      expect(find.byKey(const Key('sampleLenField')), findsNothing);
    });

    testWidgets('clearing the sample count keeps sample mode on', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      await tester.tap(find.byKey(const Key('sampleSwitch')));
      await tester.pump();
      expect(c.sampleLen, 1);

      final field = find.descendant(
        of: find.byKey(const Key('sampleLenField')),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '');
      await tester.pump();
      expect(c.sampleLen, 1);
      expect(find.byKey(const Key('sampleLenField')), findsOneWidget);

      await tester.enterText(field, '7');
      await tester.pump();
      expect(c.sampleLen, 7);
    });

    testWidgets('the resume switch writes through', (tester) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      await tester.tap(find.byKey(const Key('resumeSwitch')));
      await tester.pump();

      expect(c.resume, isTrue);
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
            'display_name': 'Gemini 3.1 Flash TTS',
          },
        },
        'defaults': {'gemini': 'Charon'},
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
        },
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
      await tester.pumpWidget(CupertinoApp(home: SettingsPanel(controller: c)));

      expect(find.byKey(const Key('settingsPanel')), findsOneWidget);
      expect(find.byKey(const Key('modelDropdown')), findsOneWidget);
      // The default fish model declares no options -> no styling-only controls.
      expect(find.byKey(const Key('useCalmTagSwitch')), findsNothing);
      expect(tester.takeException(), isNull);

      // Open the native pop-up menu and pick gemini.
      await tester.tap(find.byKey(const Key('modelDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Gemini 3.1').last);
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
}
