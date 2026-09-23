import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/platform/widgets/platform_segmented.dart';
import 'package:tts_narrator/src/gui/settings/model_voice_section.dart';

import '../support/settings_fixtures.dart';

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_model_voice_section_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpSection(WidgetTester tester, AppController c) =>
      pumpSettingsSection(tester, ModelVoiceSection(controller: c));

  group('boot', () {
    testWidgets('boots with the model and voice pickers and a collapsed '
        'advanced voice id', (tester) async {
      writeConfig(configDir, {});
      final c = makeController(configDir);
      await pumpSection(tester, c);

      expect(find.byKey(const Key('modelDropdown')), findsOneWidget);
      expect(find.byKey(const Key('voiceDropdown')), findsOneWidget);
      expect(find.byKey(const Key('voiceAdvancedDisclosure')), findsOneWidget);
      // The advanced voice id is collapsed by default.
      expect(find.byKey(const Key('voiceRawField')), findsNothing);
      expect(find.text('Overrides selected alias'), findsOneWidget);
    });
  });

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
      writeConfig(configDir, {
        'models': {'gemini': gemini},
        'defaults': {'gemini': 'Charon'},
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
        },
      });
      final c = makeController(configDir);
      await pumpSection(tester, c);
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
      writeConfig(configDir, {
        'models': {'gemini': gemini},
        'defaults': {'gemini': 'Charon'},
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
        },
      });
      final c = makeController(configDir);
      c.setVoice('my_custom_voice');
      await pumpSection(tester, c);

      await tester.tap(find.byKey(const Key('modelDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Gemini 3.1').last);
      await tester.pumpAndSettle();

      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'my_custom_voice');
    });

    testWidgets('picking a voice alias resolves to its raw id', (tester) async {
      writeConfig(configDir, {
        'default_model': 'fish',
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free', 'format': 'mp3'},
        },
        'voices': {
          'fish': {'Narrator': 'hex123'},
        },
      });
      final c = makeController(configDir);
      await pumpSection(tester, c);

      await tester.tap(find.byKey(const Key('voiceDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Narrator').last);
      await tester.pumpAndSettle();

      expect(c.voice, 'hex123');
      expect(c.voiceLabel, 'Narrator');
    });

    testWidgets('typing a raw voice id updates the controller', (tester) async {
      writeConfig(configDir, {});
      final c = makeController(configDir);
      await pumpSection(tester, c);
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
      writeConfig(configDir, {});
      final c = makeController(configDir);
      await pumpSection(tester, c);

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
      writeConfig(configDir, {
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
      final c = makeController(configDir);
      c.changeModel('kokoro');
      await pumpSection(tester, c);

      final control = tester.widget<PlatformSegmentedControl<VoiceGender>>(
        find.byKey(const Key('genderControl')),
      );
      expect(control.value, VoiceGender.neutral);
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
      // forward the "any" selection instead of treating it as no-op).
      await tester.tapAt(const Offset(600, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any'));
      await tester.pump();
      expect(c.voiceGenderFilter, VoiceGender.neutral);
      await tester.tap(find.byKey(const Key('voiceDropdown')));
      await tester.pumpAndSettle();
      expect(find.text('Emma (f)').last, findsOneWidget);
      expect(find.text('Daniel (m)').last, findsOneWidget);
    });

    testWidgets('gemini shows no voice-picker gender control without tags', (
      tester,
    ) async {
      writeConfig(configDir, {
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
      final c = makeController(configDir);
      c.changeModel('gemini');
      await pumpSection(tester, c);

      // Untagged voices -> no filter in "Model & voice" (the gender option
      // surfaces under Model options instead, covered by its own section test).
      expect(find.byKey(const Key('genderControl')), findsNothing);
    });
  });
}
