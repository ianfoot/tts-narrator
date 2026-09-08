import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/editor/editor_toolbar.dart';
import 'package:tts_narrator/src/gui/theme/app_tokens.dart' show AppThemeMode;

import '../support/fake_tts_provider.dart';
import '../support/recording_cleanup_controller.dart';

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_editor_toolbar_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AppController makeController() =>
      AppController(loader: UserVoiceConfigLoader(configDir: configDir));

  Future<void> pumpToolbar(
    WidgetTester tester,
    AppController controller, {
    bool railVisible = true,
    VoidCallback? onToggleRail,
    Future<String?> Function()? pickDirectory,
    bool playingFull = false,
    VoidCallback? onTogglePlayFull,
    void Function(String)? onShowGuard,
    VoidCallback? onCleanupSegments,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorToolbar(
            controller: controller,
            railVisible: railVisible,
            onToggleRail: onToggleRail ?? () {},
            pickDirectory: pickDirectory,
            playingFull: playingFull,
            onTogglePlayFull: onTogglePlayFull,
            onShowGuard: onShowGuard,
            onCleanupSegments: onCleanupSegments,
          ),
        ),
      ),
    );
  }

  group('toolbar controls', () {
    testWidgets('railToggleButton invokes onToggleRail', (tester) async {
      final controller = makeController();
      bool toggled = false;
      await pumpToolbar(tester, controller, onToggleRail: () => toggled = true);
      await tester.tap(find.byKey(const Key('railToggleButton')));
      expect(toggled, isTrue);
    });

    testWidgets('editorOpenButton invokes controller.onOpen', (tester) async {
      final controller = makeController();
      var opened = false;
      controller.commands.onOpen = () => opened = true;
      await pumpToolbar(tester, controller);
      await tester.tap(find.byKey(const Key('editorOpenButton')));
      expect(opened, isTrue);
    });

    testWidgets(
      'narrate blocked invokes onShowGuard and does not call onNarrate',
      (tester) async {
        final controller = makeController();
        String? guardReason;
        var narrated = false;
        controller.commands.onNarrate = () => narrated = true;
        await pumpToolbar(
          tester,
          controller,
          onShowGuard: (msg) => guardReason = msg,
        );
        await tester.tap(find.byKey(const Key('editorNarrateButton')));
        await tester.pump();
        expect(guardReason, contains('empty'));
        expect(narrated, isFalse);
      },
    );

    testWidgets('narrate unblocked calls controller.onNarrate', (tester) async {
      final controller = makeController();
      controller.setText('Some text to narrate.');
      var narrated = false;
      controller.commands.onNarrate = () => narrated = true;
      await pumpToolbar(tester, controller);
      await tester.tap(find.byKey(const Key('editorNarrateButton')));
      await tester.pump();
      expect(narrated, isTrue);
    });
  });

  group('document title', () {
    testWidgets('shows filename and dirty dot state', (tester) async {
      final controller = makeController();
      await pumpToolbar(tester, controller);
      expect(find.byKey(const Key('dirtyDot')), findsNothing);

      controller.setText('edit');
      await pumpToolbar(tester, controller);
      expect(find.byKey(const Key('dirtyDot')), findsOneWidget);
    });
  });

  group('appearance toggle', () {
    testWidgets('button renders with the system (auto) mode by default', (
      tester,
    ) async {
      final controller = makeController();
      await pumpToolbar(tester, controller);

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
      final controller = makeController();
      await pumpToolbar(tester, controller);

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
      final controller = makeController();
      await pumpToolbar(tester, controller);

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
      final controller = makeController();
      await pumpToolbar(tester, controller);
      expect(find.byKey(const Key('outDirPickerButton')), findsOneWidget);
      expect(find.byTooltip('Set output folder (⌘E)'), findsOneWidget);
    });

    testWidgets('tapping writes the chosen directory', (tester) async {
      final controller = makeController();
      await pumpToolbar(
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
      final controller = makeController();
      await pumpToolbar(tester, controller, pickDirectory: () async => null);
      await tester.tap(find.byKey(const Key('outDirPickerButton')));
      await tester.pump();
      expect(controller.outDir, 'output');
    });
  });

  group('save button', () {
    testWidgets('is disabled until the document is dirty', (tester) async {
      final controller = makeController();
      await pumpToolbar(tester, controller);
      final button = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const Key('editorSaveButton')),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('saving a dirty document clears the dirty flag', (
      tester,
    ) async {
      final controller = makeController();
      final savedPath = '${dir.path}/doc.txt';
      controller.saveLocationPicker = () async => savedPath;
      controller.setText('Some text worth saving.');
      await pumpToolbar(tester, controller);

      await tester.tap(find.byKey(const Key('editorSaveButton')));
      await tester.pump();
      expect(File(savedPath).existsSync(), isTrue);
      expect(controller.dirty, isFalse);
    });
  });

  group('full-play button', () {
    testWidgets('no full-play button until a narration run completes', (
      tester,
    ) async {
      final controller = makeController();
      controller.setText('Some text.');
      await pumpToolbar(tester, controller);
      expect(find.byKey(const Key('editorFullPlayButton')), findsNothing);
    });

    testWidgets('a completed run shows the full-play button', (tester) async {
      final controller = makeController();
      controller.setText(
        'A single paragraph long enough that it does not need any other '
        'company. It crosses the minimum word count comfortably.',
      );
      FakeTtsProvider().register();
      controller.outDir = dir.path;
      controller.startRun();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await pumpToolbar(tester, controller);
      expect(find.byKey(const Key('editorFullPlayButton')), findsOneWidget);
      expect(find.text('Play Full'), findsOneWidget);
    });

    testWidgets('a stopped run does not show the full-play button', (
      tester,
    ) async {
      final controller = makeController();
      controller.setText('First paragraph with enough words to stand alone.');
      FakeTtsProvider().register();
      controller.outDir = dir.path;
      controller.startRun();
      controller.cancelRun();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await pumpToolbar(tester, controller);
      expect(find.byKey(const Key('editorFullPlayButton')), findsNothing);
    });
  });

  group('clean-up button', () {
    testWidgets('is absent until a run leaves cleanable segments', (
      tester,
    ) async {
      final controller = RecordingCleanupController();
      await pumpToolbar(tester, controller);
      expect(find.byKey(const Key('editorCleanupButton')), findsNothing);
    });

    testWidgets('appears once a finished run has cleanable segments', (
      tester,
    ) async {
      final controller = RecordingCleanupController()
        ..cleanupUsable = true
        ..runDir = 'the run dir';
      await pumpToolbar(tester, controller);
      expect(find.byKey(const Key('editorCleanupButton')), findsOneWidget);
      expect(find.byTooltip('Clean up segments'), findsOneWidget);
    });

    testWidgets('hides again when cleanup is no longer available', (
      tester,
    ) async {
      final controller = RecordingCleanupController()
        ..cleanupUsable = true
        ..runDir = 'the run dir';
      await pumpToolbar(tester, controller);
      expect(find.byKey(const Key('editorCleanupButton')), findsOneWidget);

      controller
        ..cleanupUsable = false
        ..runDir = null;
      controller.notifyListeners();
      await tester.pump();
      expect(find.byKey(const Key('editorCleanupButton')), findsNothing);
    });

    testWidgets('tapping dispatches to onCleanupSegments', (tester) async {
      final controller = RecordingCleanupController()
        ..cleanupUsable = true
        ..runDir = 'the run dir';
      var cleaned = false;
      await pumpToolbar(
        tester,
        controller,
        onCleanupSegments: () => cleaned = true,
      );
      await tester.tap(find.byKey(const Key('editorCleanupButton')));
      expect(cleaned, isTrue);
    });
  });
}
