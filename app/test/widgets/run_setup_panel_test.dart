import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/run_setup/run_setup_panel.dart';

import '../support/l10n_test_support.dart';
import '../support/run_setup_fixtures.dart' as fixtures;
import '../support/spec_window.dart';

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
      // The row is wired to the controller, not just rendered.
      await tester.tap(find.byKey(const Key('languageDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chinese').last);
      await tester.pumpAndSettle();
      expect(c.voiceLanguage, 'zh');
      // Model options, derived because gemini declares prompt_style.
      expect(find.byKey(const Key('accentField')), findsOneWidget);
      // Run options. This is the only place these render at all: the run
      // section has no section test file of its own.
      expect(find.byKey(const Key('minWordsSlider')), findsOneWidget);
      expect(find.byKey(const Key('minWordsBadge')), findsOneWidget);
      expect(find.byKey(const Key('sampleSwitch')), findsOneWidget);
      expect(find.byKey(const Key('resumeSwitch')), findsOneWidget);
      // The badge reflects the controller default.
      expect(
        find.descendant(
          of: find.byKey(const Key('minWordsBadge')),
          matching: find.text('30'),
        ),
        findsOneWidget,
      );
    });
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
      await setSpecWindowSize(tester, const Size(1200, 1800));
      await tester.pumpWidget(testApp(home: RunSetupPanel(controller: c)));

      expect(find.byKey(const Key('runSetupPanel')), findsOneWidget);
      expect(find.byKey(const Key('modelDropdown')), findsOneWidget);

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
