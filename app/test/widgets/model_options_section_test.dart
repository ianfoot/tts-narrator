import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/run_setup/model_options_section.dart';
import 'package:tts_narrator/src/gui/widgets/app_text_field.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../support/run_setup_fixtures.dart';

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_model_options_section_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpSection(WidgetTester tester, AppController c) =>
      pumpRunSetupSection(tester, ModelOptionsSection(controller: c));

  /// Writes a single `fish` model with the given extra model-file keys, so a
  /// test can opt a model into the prompt-style and/or speed capabilities
  /// that `ModelUiSpec.forProfile` derives its controls from.
  void writeCapableFish(Map<String, Object?> extra) =>
      writeRunnableFishConfig(configDir, extra: extra);

  testWidgets('declared fields render and write through to the controller', (
    tester,
  ) async {
    writeCapableFish({'prompt_style': true});
    final c = makeController(configDir);
    await pumpSection(tester, c);

    // A prompt-styled model declares the section, so the controls exist.
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

  testWidgets('a plain model renders no model options section', (tester) async {
    writeCapableFish(const {});
    final c = makeController(configDir);
    await pumpSection(tester, c);

    expect(find.text('MODEL OPTIONS'), findsNothing);
    expect(find.byKey(const Key('accentField')), findsNothing);
  });

testWidgets('a speed-capable model renders a slider and no prompt fields', (
      tester,
    ) async {
      writeCapableFish({'speed': true});
      final c = makeController(configDir);
      await pumpSection(tester, c);

      expect(find.text('Speed'), findsOneWidget);
      expect(find.byKey(const Key('speedSlider')), findsOneWidget);
      expect(find.byKey(const Key('speedBadge')), findsOneWidget);
      expect(c.speed, 1.0);
      expect(find.byKey(const Key('accentField')), findsNothing);
      expect(find.byKey(const Key('genderOptionSegmented')), findsNothing);
    });

  testWidgets('a style hint shows as the field placeholder', (tester) async {
    writeCapableFish({'prompt_style': true});
    final c = makeController(configDir);
    await pumpSection(tester, c);

    final field = tester.widget<AppTextField>(
      find.byKey(const Key('styleField')),
    );
    expect(field.hintText, 'e.g., Warm, composed, literary');
  });

  testWidgets('a gender model option drives the narrator gender filter', (
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

    expect(find.byKey(const Key('genderOptionSegmented')), findsOneWidget);
    expect(find.text('Narrator gender'), findsOneWidget);

    // Tapping Male drives the controller's narrator gender (and its prompt
    // rewrite) for the prompt-styled model.
    await tester.tap(find.text('Male'));
    await tester.pump();
    expect(c.voiceGenderFilter, VoiceGender.male);
    expect(c.passagePrefix, contains('male narrator'));
  });

  group('voice design', () {
    testWidgets('renders the prose the model file defaults to', (tester) async {
      writeVoiceDesignConfig(configDir);
      final c = makeController(configDir);
      await pumpSection(tester, c);

      expect(find.byKey(const Key('instructField')), findsOneWidget);
      // Prefilled, not blank: the shipped model is runnable with no input.
      expect(c.instruct, contains('calm male narrator'));
      expect(find.text('Voice design'), findsOneWidget);
    });

    testWidgets('an edit reaches the controller', (tester) async {
      writeVoiceDesignConfig(configDir);
      final c = makeController(configDir);
      await pumpSection(tester, c);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('instructField')),
          matching: find.byType(CupertinoTextField),
        ),
        'A young, bright and energetic presenter.',
      );
      expect(c.instruct, 'A young, bright and energetic presenter.');
    });

    testWidgets('the prose can be cleared and left empty', (tester) async {
      // Regression: clearing the box used to mean "no override", which handed
      // the model's default prose straight back and made the field impossible
      // to empty. An empty box is a deliberate choice, not an absent one.
      writeVoiceDesignConfig(configDir);
      final c = makeController(configDir);
      await pumpSection(tester, c);

      final field = find.byKey(const Key('instructField'));
      expect(c.instruct, contains('calm male narrator'));

      await tester.enterText(
        find.descendant(of: field, matching: find.byType(CupertinoTextField)),
        '',
      );
      await tester.pump();

      expect(c.instruct, isEmpty);
      expect(tester.widget<AppTextField>(field).controller.text, isEmpty);
    });

    testWidgets('a model that takes no instruct shows no prose box', (
      tester,
    ) async {
      writeCapableFish({'prompt_style': true});
      final c = makeController(configDir);
      await pumpSection(tester, c);

      expect(find.byKey(const Key('instructField')), findsNothing);
      expect(c.instruct, isEmpty);
    });
  });
}
