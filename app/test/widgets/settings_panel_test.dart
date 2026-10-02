import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/api_key_store.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/controller/settings_controller.dart'
    show ApiKeySource;
import 'package:tts_narrator/src/gui/settings/settings_panel.dart';
import 'package:tts_narrator/src/gui/widgets/app_button.dart';
import 'package:tts_narrator/src/gui/widgets/app_text_field.dart';
import 'package:tts_narrator/src/gui/widgets/segmented_control.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../support/l10n_test_support.dart';
import '../support/settings_fixtures.dart' as fixtures;

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

  /// Writes the shared grouped config body onto the registry layout, against
  /// this group's config dir.
  void writeConfig(Map<String, Object?> body) =>
      fixtures.writeConfig(configDir, body);

  /// Pass [client] to drive narration with a fake instead of the network;
  /// omitting it keeps the real client, which is correct for tests that never
  /// start a run. [environment] defaults to empty so no test depends on what
  /// the host shell exports.
  AppController makeController({
    SpeechClient? client,
    Map<String, String>? environment,
  }) => AppController(
    loader: UserVoiceConfigLoader(
      configDir: configDir,
      environment: environment ?? const {},
    ),
    client: client,
  );

  /// Writes the starter fish config so the controller preselects fish with its
  /// default voice (as after the first-run download).
  void writeFishConfig() {
    writeConfig({
      'models': {
        'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
      },
      'defaults': {'fish': 'British Female Narrator'},
      'voices': {
        'fish': {'British Female Narrator': '89f41ea230034706881f85a8227d6ab9'},
      },
    });
  }

  /// As [writeFishConfig], but the model declares `prompt_style` and/or
  /// `speed`, which is what derives the model-options controls now that the
  /// section is config-driven instead of provider-declared.
  void writeFishConfigWith(Map<String, Object?> modelFlags) {
    writeConfig({
      'models': {
        'fish': {
          'id': 'fish-audio/s2.1-pro-free:free',
          'format': 'mp3',
          ...modelFlags,
        },
      },
      'defaults': {'fish': 'British Female Narrator'},
      'voices': {
        'fish': {'British Female Narrator': '89f41ea230034706881f85a8227d6ab9'},
      },
    });
  }

  Future<void> pumpRail(WidgetTester tester, AppController controller) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
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
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('voiceAdvancedDisclosure')),
        matching: find.text('Advanced Voice ID'),
      ),
    );
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
      final raw = tester.widget<AppTextField>(
        find.byKey(const Key('voiceRawField')),
      );
      expect(raw.controller.text, 'CN2pVME9cDEeMRXJzcMPYj0p');
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

      final control = tester.widget<SegmentedControl<VoiceGender>>(
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

    testWidgets('the kokoro panel surfaces a speed slider; fish does not', (
      tester,
    ) async {
      writeConfig({
          'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
          'kokoro': {
            'id': 'hexgrad/kokoro-82m',
            'format': 'mp3',
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
      final c = makeController();
      await pumpRail(tester, c);

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

  group('model options (derived from the model profile)', () {
    testWidgets('declared fields render and write through to the controller', (
      tester,
    ) async {
      writeFishConfigWith({'prompt_style': true});
      final c = makeController();
      await pumpRail(tester, c);

      // prompt_style derives the section, so the controls exist.
      expect(find.text('MODEL OPTIONS'), findsOneWidget);
      expect(find.byKey(const Key('accentField')), findsOneWidget);
      expect(find.byKey(const Key('styleField')), findsOneWidget);
      expect(find.byKey(const Key('passagePrefixField')), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('accentField')),
          matching: find.byType(CupertinoTextField),
        ),
        'a calm brogue',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('styleField')),
          matching: find.byType(CupertinoTextField),
        ),
        'measured, unhurried',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('passagePrefixField')),
          matching: find.byType(CupertinoTextField),
        ),
        'Read this passage.',
      );

      expect(c.accent, 'a calm brogue');
      expect(c.style, 'measured, unhurried');
      expect(c.passagePrefix, 'Read this passage.');
    });

    testWidgets('a model with no declared options renders no section', (
      tester,
    ) async {
      writeFishConfig();
      final c = makeController();
      await pumpRail(tester, c);

      expect(find.text('MODEL OPTIONS'), findsNothing);
      expect(find.byKey(const Key('accentField')), findsNothing);
      expect(find.byKey(const Key('useCalmTagSwitch')), findsNothing);
    });

    testWidgets('a speed-capable model renders a slider defaulting to 1.0', (
      tester,
    ) async {
      writeFishConfigWith({'speed': true});
      final c = makeController();
      await pumpRail(tester, c);

      expect(find.text('Speed'), findsOneWidget);
      expect(find.byKey(const Key('speedSlider')), findsOneWidget);
      expect(find.byKey(const Key('speedBadge')), findsOneWidget);
      expect(c.speed, 1.0);
    });

    testWidgets('a declared hint shows as the field placeholder', (
      tester,
    ) async {
      writeFishConfigWith({'prompt_style': true});
      final c = makeController();
      await pumpRail(tester, c);

      final field = tester.widget<CupertinoTextField>(
        find.descendant(
          of: find.byKey(const Key('styleField')),
          matching: find.byType(CupertinoTextField),
        ),
      );
      expect(field.placeholder, 'e.g., Warm, composed, literary');
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

    testWidgets('documents over 60k chars hide the whole-file toggle', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      c.setText(List.filled(maxWholeFileLength + 1, 'x').join());
      await pumpRail(tester, c);

      expect(c.wholeFileAvailable, isFalse);
      expect(find.byKey(const Key('wholeFileSwitch')), findsNothing);
      // The segment plan remains available; only whole-file is out of reach.
      expect(find.byKey(const Key('minWordsSlider')), findsOneWidget);
    });

    testWidgets('the min-words slider reflects the controller value', (
      tester,
    ) async {
      writeConfig({});
      final c = makeController();
      await pumpRail(tester, c);

      expect(c.minWords, 30);
      expect(find.byKey(const Key('minWordsSlider')), findsOneWidget);
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
          matching: find.byType(CupertinoTextField),
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
        matching: find.byType(CupertinoTextField),
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

  group('API key (secure store)', () {
    setUp(() {
      // In-memory mock keychain; a mutable map so saves can land. Reset so a
      // stored key never leaks between tests.
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    AppButton buttonWith(WidgetTester tester, String key) =>
        tester.widget<AppButton>(find.byKey(Key(key)));

    /// The API key section is collapsed by default; tap its header label (the
    /// tappable GestureDetector row, not the whole disclosure) to expand.
    Future<void> expandApiKey(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('apiKeyDisclosure')),
          matching: find.text('API key'),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows "Not set" and a disabled Remove when no key exists', (
      tester,
    ) async {
      writeFishConfig(); // no providers block -> no config/env key.
      final c = makeController();
      await pumpRail(tester, c);

      // Collapsed by default: the caption mirrors the status.
      expect(find.byKey(const Key('apiKeyField')), findsNothing);
      expect(find.text('Not set'), findsOneWidget);
      // The section header carries a tooltip explaining what the key is for.
      expect(
        find.byTooltip(testL10n.gui_settings_apiKeySectionTooltip),
        findsOneWidget,
      );

      await expandApiKey(tester);

      expect(find.byKey(const Key('apiKeyField')), findsOneWidget);
      // The empty field shows a placeholder so the input area stays visible
      // against the dark rail background.
      expect(
        find.text(testL10n.gui_settings_apiKeyFieldPlaceholder),
        findsOneWidget,
      );
      expect(find.text('Not set'), findsOneWidget);
      expect(buttonWith(tester, 'apiKeySaveButton').onPressed, isNotNull);
      expect(buttonWith(tester, 'apiKeyRemoveButton').onPressed, isNull);
    });

    testWidgets(
      'saving a key flips the status to keychain and enables Remove',
      (tester) async {
        writeFishConfig();
        final c = makeController();
        await pumpRail(tester, c);
        await expandApiKey(tester);

        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('apiKeyField')),
            matching: find.byType(CupertinoTextField),
          ),
          'sk-gui-saved',
        );
        await tester.tap(find.byKey(const Key('apiKeySaveButton')));
        await tester.pumpAndSettle();

        expect(c.hasStoredApiKey, isTrue);
        expect(c.apiKeySource, ApiKeySource.keychain);
        expect(find.text('Stored in keychain'), findsOneWidget);
        expect(buttonWith(tester, 'apiKeyRemoveButton').onPressed, isNotNull);
        // The secret never lingers in the edit box.
        final field = tester.widget<CupertinoTextField>(
          find.descendant(
            of: find.byKey(const Key('apiKeyField')),
            matching: find.byType(CupertinoTextField),
          ),
        );
        expect(field.controller!.text, isEmpty);

        // Removing clears the store and reverts the status.
        await tester.tap(find.byKey(const Key('apiKeyRemoveButton')));
        await tester.pumpAndSettle();
        expect(c.hasStoredApiKey, isFalse);
        expect(c.apiKeyMissing, isTrue);
        expect(find.text('Not set'), findsOneWidget);
      },
    );

    testWidgets('an unset \${ENV} config ref still narrates via a stored key', (
      tester,
    ) async {
      writeConfig({
          'providers': {
          'openrouter': {'api_key': r'${TTS_NARRATOR_NOT_SET}'},
        },
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
        },
        'defaults': {'fish': 'British Female Narrator'},
        'voices': {
          'fish': {
            'British Female Narrator': '89f41ea230034706881f85a8227d6ab9',
          },
        },
      });
      FlutterSecureStorage.setMockInitialValues({
        'tts-narrator.api_key.openrouter': 'sk-stored',
      });
      final store = ApiKeyStore();
      await store.load();
      final c = AppController(
        loader: UserVoiceConfigLoader(configDir: configDir),
        apiKeyStore: store,
      );
      await pumpRail(tester, c);

      // "Stored in keychain" shows as the collapsed caption.
      expect(find.text('Stored in keychain'), findsOneWidget);
      expect(c.buildConfig().providerSettings['api_key'], 'sk-stored');
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
      // gemini declares prompt_style, so switching to it derives its options.
      final c = makeController();
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(testApp(home: SettingsPanel(controller: c)));

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
      expect(find.byKey(const Key('accentField')), findsOneWidget);
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
