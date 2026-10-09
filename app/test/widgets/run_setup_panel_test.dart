import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/run_setup/run_setup_panel.dart';

import '../support/l10n_test_support.dart';
import '../support/run_setup_fixtures.dart' as fixtures;

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_run_setup_panel_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('defaults', () {
    testWidgets('boots with the fish model, its voice, and the defaults', (
      tester,
    ) async {
      fixtures.writeConfig(configDir, {});
      final c = fixtures.makeController(configDir);
      await fixtures.pumpRunSetupSection(
        tester,
        RunSetupPanel(controller: c),
      );

      expect(find.byKey(const Key('runSetupPanel')), findsOneWidget);
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

  group('composition', () {
    testWidgets('composes every section when the model declares options', (
      tester,
    ) async {
      // The one test that stays in this file's own right: it is the only place
      // that asserts the panel actually mounts every section at once. The
      // per-section behaviour lives in the section test files.
      fixtures.writeConfig(configDir, {
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'formats': ['wav'],
            'sample_rate': 24000,
            'prompt_style': true,
            'sends_language': true,
            'default_language': 'en',
            'languages': {'en': 'English', 'zh': 'Chinese'},
            'display_name': 'Gemini 3.1 Flash TTS',
          },
        },
        'defaults': {'gemini': 'Charon'},
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
        },
      });
      final c = fixtures.makeController(configDir);
      c.changeModel('gemini');
      await fixtures.pumpRunSetupSection(
        tester,
        RunSetupPanel(controller: c),
      );

      expect(find.byKey(const Key('runSetupPanel')), findsOneWidget);
      // Model & voice: the language row only renders for a model that declares
      // a language table.
      expect(find.byKey(const Key('modelDropdown')), findsOneWidget);
      expect(find.byKey(const Key('voiceDropdown')), findsOneWidget);
      expect(find.byKey(const Key('languageDropdown')), findsOneWidget);
      // Model options, derived because gemini declares prompt_style.
      expect(find.byKey(const Key('accentField')), findsOneWidget);
      // Run options.
      expect(find.byKey(const Key('minWordsSlider')), findsOneWidget);
      expect(find.byKey(const Key('sampleSwitch')), findsOneWidget);
      expect(find.byKey(const Key('resumeSwitch')), findsOneWidget);
    });
  });

  group('model & voice', () {
    testWidgets('the kokoro panel surfaces a speed slider; fish does not', (
      tester,
    ) async {
      fixtures.writeConfig(configDir, {
        'models': {
          'fish': {
            'id': 'fish-audio/s2.1-pro-free:free',
            'formats': ['mp3'],
          },
          'kokoro': {
            'id': 'hexgrad/kokoro-82m',
            'formats': ['mp3'],
            'display_name': 'Kokoro 82M',
            'speed': true,
          },
        },
        'defaults': {'kokoro': 'Emma'},
        'voices': {
          'kokoro': {
            'Alice': {'id': 'bf_alice', 'gender': 'female'},
            'Daniel': {'id': 'bm_daniel', 'gender': 'male'},
            'Emma': {'id': 'bf_emma', 'gender': 'female'},
            'Fable': {'id': 'bm_fable', 'gender': 'male'},
            'George': {'id': 'bm_george', 'gender': 'male'},
            'Isabella': {'id': 'bf_isabella', 'gender': 'female'},
            'Lewis': {'id': 'bm_lewis', 'gender': 'male'},
            'Lily': {'id': 'bf_lily', 'gender': 'female'},
          },
        },
      });
      // Kokoro declares "speed": true in its model file, so the rail offers
      // the slider for it; fish declares nothing and gets none.
      final c = fixtures.makeController(configDir);
      await fixtures.pumpRunSetupSection(
        tester,
        RunSetupPanel(controller: c),
      );

      expect(c.modelAlias, 'fish');
      expect(find.text('MODEL OPTIONS'), findsNothing);
      expect(find.byKey(const Key('speedSlider')), findsNothing);

      // Switch to kokoro: its panel gains the speed slider alongside voice.
      await tester.tap(find.byKey(const Key('modelDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Kokoro 82M').last);
      await tester.pumpAndSettle();

      expect(c.modelAlias, 'kokoro');
      expect(find.byKey(const Key('voiceAdvancedDisclosure')), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.byKey(const Key('speedSlider')), findsOneWidget);
    });

    testWidgets(
      'a voice-design model drops the voice picker but keeps the language one',
      (tester) async {
        fixtures.writeVoiceDesignConfig(configDir);
        final c = fixtures.makeController(configDir);
        await fixtures.pumpRunSetupSection(
          tester,
          RunSetupPanel(controller: c),
        );

        // No voice id is ever sent, so there is nothing to pick: the dropdown
        // and its advanced-override row both disappear rather than sitting
        // empty under a "Voice" label.
        expect(find.byKey(const Key('voiceDropdown')), findsNothing);
        expect(find.byKey(const Key('voiceAdvancedDisclosure')), findsNothing);
        // The label goes with them, so nothing dangles above the language row.
        expect(find.text('Voice alias'), findsNothing);

        // Language survives: it narrows the voice list, but it is also the
        // lang_code the model synthesises in, so this model still needs it.
        expect(find.byKey(const Key('languageDropdown')), findsOneWidget);

        // And it is not narrowed by the missing voice list: picking a language
        // used to be refused because no voice spoke it, so every choice snapped
        // back to English.
        await tester.tap(find.byKey(const Key('languageDropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chinese').last);
        await tester.pumpAndSettle();
        expect(c.voiceLanguage, 'Chinese');
        expect(find.text('Chinese'), findsWidgets);

        // Its narrator is written from prose instead, in the model options.
        expect(find.byKey(const Key('instructField')), findsOneWidget);
        expect(c.takesVoice, isFalse);
      },
    );
  });

  group('cupertino (macOS)', () {
    testWidgets('renders and switches models without Material errors', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      fixtures.writeConfig(configDir, {
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'formats': ['wav'],
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
      // gemini declares prompt_style, so switching to it derives its options.
      final c = fixtures.makeController(configDir);
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(testApp(home: RunSetupPanel(controller: c)));

      expect(find.byKey(const Key('runSetupPanel')), findsOneWidget);
      expect(find.byKey(const Key('modelDropdown')), findsOneWidget);
      // The default fish model declares no options -> no styling-only controls.
      expect(find.byKey(const Key('useCalmTagSwitch')), findsNothing);

      // Open the native pop-up menu and pick gemini.
      await tester.tap(find.byKey(const Key('modelDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Gemini 3.1').last);
      await tester.pumpAndSettle();

      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'CN2pVME9cDEeMRXJzcMPYj0p');
      expect(find.byKey(const Key('accentField')), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
