import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/settings/model_options_section.dart';

import '../support/fake_tts_provider.dart';
import '../support/settings_fixtures.dart';

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
      pumpSettingsSection(tester, ModelOptionsSection(controller: c));

  testWidgets('declared fields render and write through to the controller', (
    tester,
  ) async {
    writeFishConfig(configDir);
    final fake = FakeTtsProvider()
      ..modelUiSpec = const ModelUiSpec([
        ModelUiControl(key: 'accent', label: 'Accent'),
        ModelUiControl(key: 'style', label: 'Style / register'),
        ModelUiControl(
          key: 'passagePrefix',
          label: 'Passage prefix',
          type: ModelUiOptionType.multiline,
        ),
      ]);
    fake.register();
    final c = makeController(configDir);
    await pumpSection(tester, c);

    // The plugin declared the section, so the controls exist.
    expect(find.text('MODEL OPTIONS'), findsOneWidget);
    expect(find.byKey(const Key('accentField')), findsOneWidget);
    expect(find.byKey(const Key('styleField')), findsOneWidget);
    expect(find.byKey(const Key('passagePrefixField')), findsOneWidget);

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

    expect(c.accent, 'a calm brogue');
    expect(c.style, 'measured, unhurried');
    expect(c.passagePrefix, 'Read this passage.');
  });

  testWidgets('an empty spec renders no model options section', (tester) async {
    writeFishConfig(configDir);
    FakeTtsProvider().register();
    final c = makeController(configDir);
    await pumpSection(tester, c);

    expect(find.text('MODEL OPTIONS'), findsNothing);
    expect(find.byKey(const Key('accentField')), findsNothing);
    expect(find.byKey(const Key('useCalmTagSwitch')), findsNothing);
  });

  testWidgets('unbindable keys are ignored rather than crashing the rail', (
    tester,
  ) async {
    writeFishConfig(configDir);
    // A future plugin may declare a key this app version cannot bind; it must
    // not render and must not throw during build.
    final fake = FakeTtsProvider()
      ..modelUiSpec = const ModelUiSpec([
        ModelUiControl(key: 'speed', label: 'Speaking rate'),
        ModelUiControl(key: 'accent', label: 'Accent'),
      ]);
    fake.register();
    final c = makeController(configDir);
    await pumpSection(tester, c);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('speedField')), findsNothing);
    expect(find.byKey(const Key('accentField')), findsOneWidget);
  });

  testWidgets('a declared hint shows as the field placeholder', (tester) async {
    writeFishConfig(configDir);
    final fake = FakeTtsProvider()
      ..modelUiSpec = const ModelUiSpec([
        ModelUiControl(
          key: 'style',
          label: 'Style / register',
          hint: 'e.g. warm, restrained',
        ),
      ]);
    fake.register();
    final c = makeController(configDir);
    await pumpSection(tester, c);

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('styleField')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.decoration?.hintText, 'e.g. warm, restrained');
  });

  testWidgets('a gender model option drives the narrator gender filter', (
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
    // The real openrouter plugin surfaces gender as a Model option for
    // prompt-styled models; emulate that spec via the fake provider.
    final fake = FakeTtsProvider()
      ..modelUiSpec = const ModelUiSpec([
        ModelUiControl(
          key: 'gender',
          label: 'Narrator gender',
          type: ModelUiOptionType.gender,
        ),
      ]);
    fake.register();
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
}
