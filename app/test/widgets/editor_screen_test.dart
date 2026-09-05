import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/editor/editor_screen.dart';
import 'package:tts_narrator/src/gui/platform/widgets/platform_text_field.dart';
import 'package:tts_narrator/src/gui/settings/settings_panel.dart';
import 'package:tts_narrator/src/gui/theme/app_tokens.dart' show AppThemeMode;
import '../support/fake_audio_platform.dart';
import '../support/fake_tts_provider.dart';

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

  Future<AppController> makeController() async {
    File('$configDir/config.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder().convert({}));
    return AppController(loader: VoiceConfigLoader(configDir: configDir));
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
        home: EditorScreen(controller: controller, pickDirectory: pickDirectory),
      ),
    );
  }

  testWidgets('boots to an empty editor with a zeroed status bar', (
    tester,
  ) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);

    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.byKey(const Key('editorTextField')), findsOneWidget);
    expect(find.textContaining('0 words · 0 characters'), findsOneWidget);
    expect(
      find.textContaining('0 segments · ~0 mins · ~\$0.00 (free) est.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('editorOpenButton')), findsOneWidget);
    expect(find.byKey(const Key('editorNarrateButton')), findsOneWidget);
    // Narration is initiated from the toolbar only; the settings rail has no
    // Narrate button of its own.
    expect(find.byKey(const Key('railNarrateButton')), findsNothing);
    expect(find.byKey(const Key('railToggleButton')), findsOneWidget);
    expect(find.byTooltip('Open text file (⌘O)'), findsOneWidget);
    expect(find.text('⌘N'), findsOneWidget);
  });

  testWidgets('the status bar spans the full window and hugs the estimate pill right', (
    tester,
  ) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);
    await tester.pumpAndSettle();

    // The status bar is a sibling of the toolbar, not confined to the editor
    // column, so it spans the full window like the toolbar does.
    final screenRect = tester.getRect(find.byType(EditorScreen));
    final barRect = tester.getRect(find.byKey(const Key('statusBar')));
    expect(barRect.left, screenRect.left);
    expect(barRect.right, closeTo(screenRect.right, 1));

    // The estimate pill announces the bar's right edge rather than floating
    // at a hardcoded midpoint: the bar's 16px horizontal padding plus the
    // pill's 4px inner padding inset the text from the window edge.
    final estimateRight = tester.getBottomRight(
      find.byKey(const Key('editorEstimate')),
    );
    expect(estimateRight.dx, closeTo(barRect.right - 16 - 4, 1));
  });

  testWidgets('the settings rail is visible by default and toggles away', (
    tester,
  ) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);

    expect(find.byType(SettingsPanel), findsOneWidget);

    await tester.tap(find.byKey(const Key('railToggleButton')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsNothing);

    await tester.tap(find.byKey(const Key('railToggleButton')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsOneWidget);
  });

  testWidgets('a controller-driven panel toggle hides and restores the rail', (
    tester,
  ) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);

    expect(find.byType(SettingsPanel), findsOneWidget);

    controller.toggleSettingsPanel();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsNothing);

    controller.toggleSettingsPanel();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsOneWidget);
  });

  testWidgets('macOS editor text is top-aligned in the expanding field', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final controller = await makeController();
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CupertinoApp(home: EditorScreen(controller: controller)),
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
      ..writeAsStringSync('A freshly opened chapter with plenty of words in '
          'it to narrate out loud.');
    controller.loadFromFile(story.path);

    await pumpEditor(tester, controller);

    final field = tester.widget<PlatformTextField>(
      find.byKey(const Key('editorTextField')),
    );
    expect(field.controller!.text, contains('freshly opened chapter'));
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
    controller.onNarrate = () => narrated = true;
    controller.setText('Some real text to narrate.');
    await pumpEditor(tester, controller);

    await tester.tap(find.byKey(const Key('editorNarrateButton')));
    await tester.pump();

    expect(narrated, isTrue);
    expect(find.byKey(const Key('narrateGuard')), findsNothing);
  });

  testWidgets('no full-play button until a narration run completes', (
    tester,
  ) async {
    final controller = await makeController();
    controller.setText('Some real text to narrate.');
    await pumpEditor(tester, controller);
    expect(find.byKey(const Key('editorFullPlayButton')), findsNothing);
  });

  testWidgets('a completed run shows the full-play button', (tester) async {
    final controller = await makeController();
    controller.setText(
      'A single paragraph long enough that it does not need any other '
      'company. It crosses the minimum word count comfortably and becomes '
      'one segment all on its own, plain and simple.',
    );
    FakeTtsProvider().register();
    controller.outDir = dir.path;
    controller.startRun();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    await pumpEditor(tester, controller);
    expect(controller.runFinished, isTrue);
    expect(controller.completedAudioPath, isNotNull);
    expect(find.byKey(const Key('editorFullPlayButton')), findsOneWidget);
    expect(find.text('Play Full'), findsOneWidget);
  });

  testWidgets('full-play button toggles to Stop and reverts on clip end', (
    tester,
  ) async {
    final audio = installFakeAudioPlatform();
    final controller = await makeController();
    controller.setText(
      'A single paragraph long enough that it does not need any other '
      'company. It crosses the minimum word count comfortably and becomes '
      'one segment all on its own, plain and simple.',
    );
    FakeTtsProvider().register();
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

  testWidgets('a stopped run does not show the full-play button', (
    tester,
  ) async {
    final controller = await makeController();
    controller.setText(
      'First paragraph with enough words to become its own segment and then '
      'carry on a little longer to cross the minimum.\n\n'
      'Second paragraph with enough words to become its own segment as well '
      'and then carry on a little longer to cross the minimum.',
    );
    FakeTtsProvider().register();
    controller.outDir = dir.path;
    controller.startRun();
    controller.cancelRun();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    await pumpEditor(tester, controller);
    expect(controller.runStopped, isTrue);
    expect(controller.completedAudioPath, isNull);
    expect(find.byKey(const Key('editorFullPlayButton')), findsNothing);
  });

  testWidgets('starting a new run stops playback of the prior track', (
    tester,
  ) async {
    installFakeAudioPlatform();
    final controller = await makeController();
    controller.setText(
      'A single paragraph long enough that it does not need any other '
      'company. It crosses the minimum word count comfortably and becomes '
      'one segment all on its own, plain and simple.',
    );
    FakeTtsProvider().register();
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

  group('appearance toggle', () {
    testWidgets('button renders with the system (auto) mode by default', (
      tester,
    ) async {
      final controller = await makeController();
      await pumpEditor(tester, controller);

      expect(find.byKey(const Key('appearanceToggleButton')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('appearanceToggleButton')),
          matching: find.byIcon(Icons.brightness_auto),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping cycles system -> light -> dark -> system', (
      tester,
    ) async {
      final controller = await makeController();
      await pumpEditor(tester, controller);

      await tester.tap(find.byKey(const Key('appearanceToggleButton')));
      expect(controller.themeMode, AppThemeMode.light);
      await tester.tap(find.byKey(const Key('appearanceToggleButton')));
      expect(controller.themeMode, AppThemeMode.dark);
      await tester.tap(find.byKey(const Key('appearanceToggleButton')));
      expect(controller.themeMode, AppThemeMode.system);
    });

    testWidgets('button icon follows a controller-driven mode change', (
      tester,
    ) async {
      final controller = await makeController();
      await pumpEditor(tester, controller);

      controller.themeMode = AppThemeMode.dark;
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('appearanceToggleButton')),
          matching: find.byIcon(Icons.dark_mode),
        ),
        findsOneWidget,
      );
    });
  });

  group('output folder', () {
    testWidgets('shows the output-folder button with a tooltip', (
      tester,
    ) async {
      final controller = await makeController();
      await pumpEditor(tester, controller);

      expect(find.byKey(const Key('outDirPickerButton')), findsOneWidget);
      expect(find.byTooltip('Set output folder (⌘E)'), findsOneWidget);
    });

    testWidgets('tapping writes the chosen directory', (tester) async {
      final controller = await makeController();
      await pumpEditor(
        tester,
        controller,
        pickDirectory: () async => '/picked/audio',
      );

      await tester.tap(find.byKey(const Key('outDirPickerButton')));
      await tester.pump();

      expect(controller.outDir, '/picked/audio');
    });

    testWidgets('cancelling the picker leaves the directory unchanged', (
      tester,
    ) async {
      final controller = await makeController();
      await pumpEditor(
        tester,
        controller,
        pickDirectory: () async => null,
      );

      await tester.tap(find.byKey(const Key('outDirPickerButton')));
      await tester.pump();

      expect(controller.outDir, 'output');
    });
  });
}
