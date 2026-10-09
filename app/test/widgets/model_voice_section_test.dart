import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/run_setup/model_voice_section.dart';
import 'package:tts_narrator/src/gui/widgets/app_text_field.dart';
import 'package:tts_narrator/src/gui/widgets/segmented_control.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../support/run_setup_fixtures.dart';

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
      pumpRunSetupSection(tester, ModelVoiceSection(controller: c));

  /// Opens the dropdown with key [key] and picks the entry [label].
  ///
  /// Every picker in this section is the same gesture on a different key. The
  /// `.last` is what selects the entry out of the open overlay, which repeats
  /// the closed button's own label; [exact] is false where the entry is
  /// identified by part of its name rather than all of it.
  Future<void> pickFrom(
    WidgetTester tester,
    String key,
    String label, {
    bool exact = true,
  }) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(
      (exact ? find.text(label) : find.textContaining(label)).last,
    );
    await tester.pumpAndSettle();
  }

  Future<void> switchModelTo(WidgetTester tester, String label) =>
      pickFrom(tester, 'modelDropdown', label, exact: false);

  Future<void> pickVoice(WidgetTester tester, String label) =>
      pickFrom(tester, 'voiceDropdown', label);

  Future<void> pickLanguage(WidgetTester tester, String label) =>
      pickFrom(tester, 'languageDropdown', label);

  /// Opens the voice menu without choosing from it, for tests that only read
  /// what it offers.
  Future<void> openVoiceMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('voiceDropdown')));
    await tester.pumpAndSettle();
  }

  /// Dismisses the open menu by tapping well clear of it.
  Future<void> closeMenus(WidgetTester tester) async {
    await tester.tapAt(const Offset(600, 100));
    await tester.pumpAndSettle();
  }

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
      'formats': ['wav'],
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

      await switchModelTo(tester, 'Gemini 3.1');

      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'CN2pVME9cDEeMRXJzcMPYj0p');
      expect(c.voiceLabel, 'Charon');
      // The raw id field follows the new default.
      final raw = tester.widget<AppTextField>(
        find.byKey(const Key('voiceRawField')),
      );
      expect(raw.controller.text, 'CN2pVME9cDEeMRXJzcMPYj0p');
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

      await switchModelTo(tester, 'Gemini 3.1');

      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'my_custom_voice');
    });

    testWidgets('picking a voice alias resolves to its raw id', (tester) async {
      writeConfig(configDir, {
        'models': {
          'fish': {
            'id': 'fish-audio/s2.1-pro-free',
            'formats': ['mp3'],
          },
        },
        'voices': {
          'fish': {'Narrator': 'hex123'},
        },
      });
      final c = makeController(configDir);
      await pumpSection(tester, c);

      await pickVoice(tester, 'Narrator');

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
          matching: find.byType(CupertinoTextField),
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
          'kokoro': {
            'id': 'hexgrad/kokoro-82m',
            'formats': ['mp3'],
          },
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

      final control = tester.widget<SegmentedControl<VoiceGender>>(
        find.byKey(const Key('genderControl')),
      );
      expect(control.value, VoiceGender.neutral);
      expect(control.items.map((it) => it.$2), ['Any', 'Female', 'Male']);

      // Female voices get a compact shorthand in the dropdown.
      await openVoiceMenu(tester);
      expect(find.text('Emma (f)').last, findsOneWidget);
      expect(find.text('Alice (f)').last, findsOneWidget);
      // Close the open dropdown.
      await closeMenus(tester);

      // Switch to Male: the filter narrows the picker and auto-selects.
      await tester.tap(find.text('Male'));
      await tester.pump();
      expect(c.voiceGenderFilter, VoiceGender.male);
      expect(c.voiceLabel, 'Daniel');

      await openVoiceMenu(tester);
      expect(find.text('Daniel (m)').last, findsOneWidget);
      expect(find.text('Fable (m)').last, findsOneWidget);
      expect(find.text('Emma (f)'), findsNothing);

      // Back to Any: the picker returns to the full list (Material path must
      // forward the "any" selection instead of treating it as no-op).
      await closeMenus(tester);
      await tester.tap(find.text('Any'));
      await tester.pump();
      expect(c.voiceGenderFilter, VoiceGender.neutral);
      await openVoiceMenu(tester);
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
            'formats': ['wav'],
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

    testWidgets(
      'language dropdown filters the voices for a multilingual model',
      (tester) async {
        writeConfig(configDir, {
          'models': {
            'kokoro': {
              'id': 'hexgrad/kokoro-82m',
              'formats': ['mp3'],
              'sends_language': true,
              'default_language': 'b',
              'languages': {
                'a': 'American English',
                'b': 'British English',
                'j': 'Japanese',
              },
            },
          },
          'defaults': {'kokoro': 'Emma'},
          'voices': {
            'kokoro': {
              'Aria': {'id': 'af_heart', 'gender': 'female'},
              'Alice': {'id': 'bf_alice', 'gender': 'female'},
              'Emma': {'id': 'bf_emma', 'gender': 'female'},
              'Kumo': {'id': 'jm_kumo', 'gender': 'male'},
            },
          },
        });
        final c = makeController(configDir);
        c.changeModel('kokoro');
        await pumpSection(tester, c);

        // The model's `default_language` preselects British English, and the
        // voice list starts narrowed to it.
        expect(find.byKey(const Key('languageDropdown')), findsOneWidget);
        expect(c.voiceLanguage, 'b');
        await tester.tap(find.byKey(const Key('voiceDropdown')));
        await tester.pumpAndSettle();
        expect(find.text('Emma (f)').last, findsOneWidget);
        expect(find.text('Kumo (m)'), findsNothing);
        await tester.tapAt(const Offset(600, 100));
        await tester.pumpAndSettle();

        // Switching to Japanese narrows the voices and re-picks one.
        await pickLanguage(tester, 'Japanese');

        expect(c.voiceLanguage, 'j');
        expect(c.voiceLabel, 'Kumo');
        await tester.tap(find.byKey(const Key('voiceDropdown')));
        await tester.pumpAndSettle();
        expect(find.text('Kumo (m)').last, findsOneWidget);
        expect(find.text('Emma (f)'), findsNothing);
      },
    );

    testWidgets('a single-language model shows no language dropdown', (
      tester,
    ) async {
      writeConfig(configDir, {
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'formats': ['wav'],
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

      expect(find.byKey(const Key('languageDropdown')), findsNothing);
    });

    testWidgets('voices keyed by id show their names and send their own id', (
      tester,
    ) async {
      writeConfig(configDir, {
        'models': {
          'kokoro': {
            'id': 'hexgrad/kokoro-82m',
            'formats': ['mp3'],
            'sends_language': true,
            'default_language': 'b',
            'languages': {
              'b': 'British English',
              'e': 'Spanish',
              'p': 'Brazilian Portuguese',
            },
          },
        },
        'defaults': {'kokoro': 'bf_emma'},
        'voices': {
          'kokoro': {
            'bf_emma': {'name': 'Emma'},
            'em_santa': {'name': 'Santa'},
            'pm_santa': {'name': 'Santa'},
          },
        },
      });
      final c = makeController(configDir);
      c.changeModel('kokoro');
      await pumpSection(tester, c);

      // The picker shows each voice's `name`, never its `voices` key.
      await openVoiceMenu(tester);
      expect(find.text('Emma (f)').last, findsOneWidget);
      await closeMenus(tester);

      // Two voices may share a name, so the id is what has to disambiguate:
      // Spanish's Santa sends em_santa...
      await pickLanguage(tester, 'Spanish');
      expect(c.voiceLabel, 'Santa');
      expect(c.voice, 'em_santa');

      // ...and Brazilian Portuguese's sends pm_santa, same label and all.
      await pickLanguage(tester, 'Brazilian Portuguese');
      expect(c.voiceLabel, 'Santa');
      expect(c.voice, 'pm_santa');
    });
  });

  group('output format', () {
    // A model that lists both formats, wav first, the way the local
    // mlx-audio-backed models ship.
    const dualFormat = {
      'id': 'mlx-community/Kokoro-82M-4bit',
      'formats': ['wav', 'mp3'],
    };

    testWidgets('a model offering one format shows no format control', (
      tester,
    ) async {
      writeConfig(configDir, {
        'models': {
          'kokoro': {
            'id': 'hexgrad/kokoro-82m',
            'formats': ['mp3'],
          },
        },
      });
      final c = makeController(configDir);
      c.changeModel('kokoro');
      await pumpSection(tester, c);

      expect(find.byKey(const Key('formatControl')), findsNothing);
      // The single format is still what the run uses.
      expect(c.outputFormat, TtsAudioFormat.mp3);
    });

    testWidgets('a model offering both formats shows them in declared order', (
      tester,
    ) async {
      writeConfig(configDir, {
        'models': {'local': dualFormat},
      });
      final c = makeController(configDir);
      c.changeModel('local');
      await pumpSection(tester, c);

      final control = tester.widget<SegmentedControl<TtsAudioFormat>>(
        find.byKey(const Key('formatControl')),
      );
      expect(control.items.map((it) => it.$1), [
        TtsAudioFormat.wav,
        TtsAudioFormat.mp3,
      ]);
      // The first declared format is the model's own default.
      expect(control.value, TtsAudioFormat.wav);
      expect(c.outputFormat, TtsAudioFormat.wav);
    });

    testWidgets('picking a format updates the controller', (tester) async {
      writeConfig(configDir, {
        'models': {'local': dualFormat},
      });
      final c = makeController(configDir);
      c.changeModel('local');
      await pumpSection(tester, c);

      await tester.tap(find.text('MP3'));
      await tester.pumpAndSettle();

      expect(c.outputFormat, TtsAudioFormat.mp3);

      final control = tester.widget<SegmentedControl<TtsAudioFormat>>(
        find.byKey(const Key('formatControl')),
      );
      expect(control.value, TtsAudioFormat.mp3);
    });

    testWidgets('each model keeps its own choice', (tester) async {
      writeConfig(configDir, {
        'models': {
          'local': dualFormat,
          'kokoro': {
            'id': 'hexgrad/kokoro-82m',
            'formats': ['mp3'],
          },
        },
      });
      final c = makeController(configDir);
      c.changeModel('local');
      c.outputFormat = TtsAudioFormat.mp3;
      await pumpSection(tester, c);

      c.changeModel('kokoro');
      await tester.pumpAndSettle();
      // Kokoro only offers mp3, so its choice follows what it can serve.
      expect(c.outputFormat, TtsAudioFormat.mp3);

      c.changeModel('local');
      await tester.pumpAndSettle();
      expect(c.outputFormat, TtsAudioFormat.mp3);
    });
  });
}
