import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/editor/editor_screen.dart';
import 'package:tts_narrator/src/gui/platform/platform_detection.dart'
    show acceleratorLabel;
import 'package:tts_narrator/src/gui/run_setup/run_setup_panel.dart';
import 'package:tts_narrator/src/gui/widgets/app_text_field.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../support/fake_audio_platform.dart';
import '../support/fake_tts_provider.dart';
import '../support/l10n_test_support.dart';
import '../support/run_setup_fixtures.dart' as fixtures;

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_editor_test_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void writeFishConfig() => fixtures.writeRunnableFishConfig(configDir);

  Future<AppController> makeController({SpeechClient? client}) async {
    writeFishConfig();
    return AppController(
      loader: UserVoiceConfigLoader(configDir: configDir),
      client: client,
    );
  }

  Future<void> pumpEditor(
    WidgetTester tester,
    AppController controller, {
    Future<String?> Function()? pickDirectory,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: EditorScreen(
          controller: controller,
          pickDirectory: pickDirectory,
        ),
      ),
    );
  }

  testWidgets('boots to an empty editor with a zeroed status bar', (
    tester,
  ) async {
    final controller = await makeController(client: FakeTtsProvider().client);
    await pumpEditor(tester, controller);

    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.byKey(const Key('editorTextField')), findsOneWidget);
    expect(find.byKey(const Key('editorOpenButton')), findsOneWidget);
    expect(find.byKey(const Key('editorNarrateButton')), findsOneWidget);
    // Narration is initiated from the toolbar only; the run-setup panel has no
    // Narrate button of its own.
    expect(find.byKey(const Key('railNarrateButton')), findsNothing);
    expect(find.byKey(const Key('runSetupToggleButton')), findsOneWidget);
    expect(
      find.byTooltip(
        '${testL10n.gui_editor_toolbar_openTextFile} '
        '(${acceleratorLabel('O')})',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip(
        '${testL10n.gui_editor_toolbar_narrate} (${acceleratorLabel('N')})',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the run-setup panel is visible by default and toggles away', (
    tester,
  ) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);

    expect(find.byType(RunSetupPanel), findsOneWidget);

    await tester.tap(find.byKey(const Key('runSetupToggleButton')));
    await tester.pumpAndSettle();
    expect(find.byType(RunSetupPanel), findsNothing);

    await tester.tap(find.byKey(const Key('runSetupToggleButton')));
    await tester.pumpAndSettle();
    expect(find.byType(RunSetupPanel), findsOneWidget);
  });

  testWidgets('a controller-driven panel toggle hides and restores the rail', (
    tester,
  ) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);

    expect(find.byType(RunSetupPanel), findsOneWidget);

    controller.toggleRunSetupPanel();
    await tester.pumpAndSettle();
    expect(find.byType(RunSetupPanel), findsNothing);

    controller.toggleRunSetupPanel();
    await tester.pumpAndSettle();
    expect(find.byType(RunSetupPanel), findsOneWidget);
  });

  testWidgets('macOS editor text is top-aligned in the expanding field', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final controller = await makeController();
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      testApp(home: EditorScreen(controller: controller)),
    );

    final field = tester.widget<CupertinoTextField>(
      find.descendant(
        of: find.byKey(const Key('editorTextField')),
        matching: find.byType(CupertinoTextField),
      ),
    );
    expect(field.textAlignVertical, TextAlignVertical.top);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('typing updates the status bar word/char/estimate', (
    tester,
  ) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);

    await tester.enterText(
      find.byKey(const Key('editorTextField')),
      'The rain fell on the quiet street. Lights glowed behind the windows.',
    );
    // Settle the 100ms status-bar ticker so the previous AnimatedSwitcher
    // child is gone before asserting on the single live readout.
    await tester.pumpAndSettle();

    expect(find.textContaining('12 words · '), findsOneWidget);
    expect(find.textContaining('1 segment'), findsOneWidget);
    expect(find.textContaining('~\$0.00 (free) est.'), findsOneWidget);
    expect(find.byKey(const Key('dirtyDot')), findsOneWidget);
  });

  testWidgets('a controller-loading document appears in the editor', (
    tester,
  ) async {
    final controller = await makeController();
    final story = File('${dir.path}/story.txt')
      ..writeAsStringSync(
        'A freshly opened chapter with plenty of words in '
        'it to narrate out loud.',
      );
    controller.loadFromFile(story.path);

    await pumpEditor(tester, controller);

    final field = tester.widget<AppTextField>(
      find.byKey(const Key('editorTextField')),
    );
    expect(field.controller.text, contains('freshly opened chapter'));
    expect(find.textContaining('story.txt'), findsOneWidget);
    expect(controller.dirty, isFalse);
    expect(find.byKey(const Key('dirtyDot')), findsNothing);
  });

  testWidgets('Narrate on an empty document shows the guard banner', (
    tester,
  ) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);

    await tester.tap(find.byKey(const Key('editorNarrateButton')));
    await tester.pump();

    expect(find.byKey(const Key('narrateGuard')), findsOneWidget);
    expect(
      find.textContaining('Cannot narrate: Editor text is empty'),
      findsOneWidget,
    );

    // The banner auto-dismisses after the guard timer (plus the exit
    // animation), so settle the AnimatedSwitcher before asserting it's gone.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('narrateGuard')), findsNothing);
  });

  testWidgets('Narrate with text dispatches through the onNarrate slot', (
    tester,
  ) async {
    final controller = await makeController();
    var narrated = false;
    controller.commands.onNarrate = () => narrated = true;
    controller.setText('Some real text to narrate.');
    await pumpEditor(tester, controller);

    await tester.tap(find.byKey(const Key('editorNarrateButton')));
    await tester.pump();

    expect(narrated, isTrue);
    expect(find.byKey(const Key('narrateGuard')), findsNothing);
  });

  testWidgets('full-play button toggles to Stop and reverts on clip end', (
    tester,
  ) async {
    final audio = installFakeAudioPlatform();
    final controller = await makeController(client: FakeTtsProvider().client);
    controller.setText(
      'A single paragraph long enough that it does not need any other '
      'company. It crosses the minimum word count comfortably and becomes '
      'one segment all on its own, plain and simple.',
    );
    controller.outDir = dir.path;
    controller.startRun();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await pumpEditor(tester, controller);
    expect(find.byKey(const Key('editorFullPlayButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('editorFullPlayButton')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);

    audio.emitComplete();
    await tester.pump();
    expect(find.text('Play Full'), findsOneWidget);
  });

  testWidgets('starting a new run stops playback of the prior track', (
    tester,
  ) async {
    installFakeAudioPlatform();
    final controller = await makeController(client: FakeTtsProvider().client);
    controller.setText(
      'A single paragraph long enough that it does not need any other '
      'company. It crosses the minimum word count comfortably and becomes '
      'one segment all on its own, plain and simple.',
    );
    controller.outDir = dir.path;

    // First run completes and starts playing.
    controller.startRun();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await pumpEditor(tester, controller);
    await tester.tap(find.byKey(const Key('editorFullPlayButton')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);

    // A second run clears the completed path mid-playback; the prior track
    // must stop and the button must not be left in a stale Stop state.
    controller.setText(
      'A different single paragraph long enough to stand alone too. It '
      'easily crosses the minimum word count and becomes its own segment, '
      'just like the first one did before it.',
    );
    controller.startRun();
    expect(controller.completedAudioPath, isNull);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();

    expect(controller.runFinished, isTrue);
    expect(find.text('Play Full'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
  });

  group('editing the document', () {
    testWidgets('deleting every character leaves the editor empty', (
      tester,
    ) async {
      // Regression: the editor wrote the field's own text back into the
      // TextEditingController from inside the change listener, so erasing the
      // document re-materialised the text instead of clearing it.
      final controller = await makeController();
      await pumpEditor(tester, controller);

      await tester.enterText(
        find.byType(AppTextField),
        'Sample text the user is replacing.',
      );
      await tester.pump();
      expect(controller.text, 'Sample text the user is replacing.');

      await tester.enterText(find.byType(AppTextField), '');
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(find.text('Sample text the user is replacing.'), findsNothing);
    });

    testWidgets(
      'typing stays in step with the field, one character at a time',
      (tester) async {
        final controller = await makeController();
        await pumpEditor(tester, controller);

        final field = find.byType(AppTextField);
        for (final partial in ['S', 'Sa', 'Sam', 'Samp', 'Sampl']) {
          await tester.enterText(field, partial);
          await tester.pump();
          expect(controller.text, partial);
        }
      },
    );

    testWidgets('backspacing the text away does not bring it back', (
      tester,
    ) async {
      // The real gesture, as opposed to enterText: real key events go through
      // the text input connection, so the change listener fires while the
      // field is still mid-edit rather than after it has settled.
      final controller = await makeController();
      await pumpEditor(tester, controller);

      await tester.enterText(find.byType(AppTextField), 'Sample text.');
      await tester.pump();

      for (var i = 0; i < 'Sample text.'.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(
          controller.text.length,
          'Sample text.'.length - i - 1,
          reason: 'after ${i + 1} backspace(s)',
        );
      }

      expect(controller.text, isEmpty);
    });

    testWidgets('a load still replaces the text in the field', (tester) async {
      // The other direction must keep working: a load is not a keystroke, so
      // the field has to be told about it.
      final controller = await makeController();
      await pumpEditor(tester, controller);

      final file = File('${dir.path}/sample.txt')
        ..writeAsStringSync('Loaded from disk.');
      controller.loadFromFile(file.path);
      await tester.pump();

      expect(controller.text, 'Loaded from disk.');
      expect(find.text('Loaded from disk.'), findsOneWidget);
    });
  });
}
