import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/narration/narration_screen.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../support/fake_audio_platform.dart';
import '../support/fake_tts_provider.dart';
import '../support/l10n_test_support.dart';
import '../support/settings_fixtures.dart' as fixtures;

/// Speech client whose [synthesize] never returns: keeps a run in-flight so
/// Cancel and the active-run Back confirm modal are meaningful.
class _BlockingClient {
  SpeechClient get client => synthesize;

  Future<GeneratedAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
    required double? speed,
    AbortToken? abort,
  }) async {
    await Completer<void>().future;
    abort?.throwIfCancelled();
    return GeneratedAudio(bytes: const [0]);
  }
}

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_narration_screen_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Writes the starter fish config so the controller has a resolvable default
  /// model, as after the first-run download; without it no model is configured
  /// and runs cannot start.
  void writeFishConfig() {
    fixtures.writeConfig(configDir, {
      'providers': {
        // A real model is served by the real (key-requiring) OpenRouter
        // provider; give the fixture a dummy key so run-plan building
        // succeeds regardless of the fake provider registered here, and a
        // base_url so `narrate`'s up-front block check passes.
        'openrouter': {
          'base_url': 'https://openrouter.ai/api/v1',
          'api_key': 'sk-test',
        },
      },
      'models': {
        'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
      },
      'defaults': {'fish': 'British Female Narrator'},
      'voices': {
        'fish': {'British Female Narrator': '89f41ea230034706881f85a8227d6ab9'},
      },
    });
  }

  AppController makeController({SpeechClient? client}) {
    writeFishConfig();
    final c = AppController(
      loader: UserVoiceConfigLoader(configDir: configDir),
      client: client,
    )..outDir = dir.path;
    c.setText(
      'The rain fell on the quiet street all through the long cold night and '
      'every window glowed warm behind drawn curtains as the story of the '
      'small town slowly unfolded towards its patient and inevitable end.\n'
      '\n'
      'When morning finally came the streets were washed clean and bright and '
      'the light spilled across the rooftops like a still and gentle promise '
      'that the day ahead would be calm and full of quiet ordinary wonder.\n',
    );
    return c;
  }

  Future<void> pumpRun(WidgetTester tester, AppController controller) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: NarrationScreen(controller: controller),
      ),
    );
  }

  /// Pumps the run view as a *pushed* route above an editor placeholder so a
  /// confirmed Back actually pops the view (the `home:` variant cannot pop).
  Future<void> pumpPushedRun(
    WidgetTester tester,
    AppController controller,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: Text('EDITOR', key: const Key('editorHost'))),
          ),
        ),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => NarrationScreen(controller: controller),
      ),
    );
    // Fixed pumps, not pumpAndSettle: an active run renders an ever-animating
    // spinner that would never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('a launched run renders the header and frozen summary pill', (
    tester,
  ) async {
    final fake = FakeTtsProvider();
    final c = makeController(client: fake.client)..sampleLen = 1;
    c.startRun();
    await pumpRun(tester, c);

    expect(find.text('Narrating: untitled.txt'), findsOneWidget);
    expect(find.byKey(const Key('runHeaderTitle')), findsOneWidget);
    final pill = tester.widget<Text>(find.byKey(const Key('runSummaryPill')));
    expect(pill.data, contains('1 segment · '));
    expect(pill.data, contains('·'));
    expect(find.byKey(const Key('runProgressBar')), findsOneWidget);
    expect(find.byKey(const Key('runBackButton')), findsOneWidget);
    expect(find.byKey(const Key('runActionBack')), findsOneWidget);

    // Let the single segment land; then Cancel disappears and segments are done.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('runCancelButton')), findsNothing);
    expect(find.textContaining('Narration complete.'), findsOneWidget);
    expect(fake.callCount, 1);
    expect(c.totalSegments, 1);
    expect(c.runDoneCount, 1);
    expect(c.runProgress, 1.0);
    expect(find.byKey(const Key('segStatus_completed_0')), findsOneWidget);
    expect(find.byKey(const Key('segAction_0')), findsOneWidget);
    expect(find.text('Segment 1'), findsOneWidget);
  });

  testWidgets('empty-text plan failure renders the plan-error banner', (
    tester,
  ) async {
    writeFishConfig();
    final c = AppController(
      loader: UserVoiceConfigLoader(configDir: configDir),
      client: FakeTtsProvider().client,
    )..outDir = dir.path;
    c.startRun();
    await pumpRun(tester, c);

    expect(find.textContaining('No paragraphs found'), findsOneWidget);
    expect(find.byKey(const Key('runCancelButton')), findsNothing);
  });

  testWidgets('segment cards render all four status states in 3 columns', (
    tester,
  ) async {
    final c = makeController(client: FakeTtsProvider().client)..sampleLen = 2;
    c.startRun();
    await pumpRun(tester, c);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.runFinished, isTrue);

    // Recast the two real segments plus two synthetic ones to cover every state.
    c.runSegments[0].filePath = null; // pending
    // segment 1 stays completed (its clip landed on disk during the run).
    final resumedFile = File('${dir.path}/resumed.wav')..writeAsStringSync('x');
    c.runSegments.addAll([
      NarrationSegment(index: 2, paragraph: 'A third passage is processing.')
        ..running = true,
      NarrationSegment(index: 3, paragraph: 'A reused fourth passage.')
        ..resumed = true
        ..filePath = resumedFile.path,
    ]);
    c.notifyListeners();
    await tester.pump();

    // Col 1 status indicators.
    expect(find.byKey(const Key('segStatus_pending_0')), findsOneWidget);
    expect(find.byKey(const Key('segStatus_completed_1')), findsOneWidget);
    expect(find.byKey(const Key('segStatus_processing_2')), findsOneWidget);
    expect(find.byKey(const Key('segStatus_resumed_3')), findsOneWidget);

    // Col 2 body: bold label + word count + preview.
    expect(find.text('Segment 1'), findsOneWidget);
    expect(find.text('Segment 2'), findsOneWidget);
    expect(find.text('Segment 3'), findsOneWidget);
    expect(find.text('Segment 4'), findsOneWidget);
    expect(find.textContaining('words'), findsWidgets);

    // Col 3 actions: pending/processing labels; Play for completed + reused.
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Processing...'), findsOneWidget);
    expect(find.text('Play'), findsNWidgets(2));
    expect(find.byTooltip('Resumed — tap to play'), findsOneWidget);
  });

  testWidgets('Play toggles to Stop and reverts on clip end and manual stop', (
    tester,
  ) async {
    final audio = installFakeAudioPlatform();
    final c = makeController(client: FakeTtsProvider().client)..sampleLen = 1;
    c.startRun();
    await pumpRun(tester, c);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.runFinished, isTrue);

    // Play -> Stop (single active clip).
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);

    // Reaching the end of the clip auto-reverts the button to Play.
    audio.emitComplete();
    await tester.pump();
    expect(find.text('Play'), findsOneWidget);

    // Play again, then manual Stop reverts without a platform completion.
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('Cancel Run stops a running narration', (tester) async {
    final c = makeController(client: _BlockingClient().client)..sampleLen = 5;
    c.startRun();
    await pumpRun(tester, c);

    expect(find.byKey(const Key('runCancelButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('runCancelButton')));
    await tester.pump();

    expect(c.runStopped, isTrue);
    expect(find.textContaining('Narration was stopped.'), findsOneWidget);
    expect(find.byKey(const Key('runCancelButton')), findsNothing);
  });

  testWidgets('Back during an active run prompts and Cancel Run leaves', (
    tester,
  ) async {
    final c = makeController(client: _BlockingClient().client)..sampleLen = 3;
    c.startRun();
    await pumpRun(tester, c);

    // Back while generating opens the confirm modal.
    await tester.tap(find.byKey(const Key('runBackButton')).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Cancel active narration run?'), findsOneWidget);

    // The dialog's "Back" keeps the run going and stays on the run view.
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.text('Back'),
      ),
    );
    // pumpAndSettle can't be used while narrating: the progress animation
    // never settles. Pump past the dialog's dismiss transition instead.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Cancel active narration run?'), findsNothing);
    expect(c.narrating, isTrue);

    // Retry and confirm with "Cancel Run": the run stops and the view pops.
    await tester.tap(find.byKey(const Key('runBackButton')).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.text('Cancel Run'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.runStopped, isTrue);
    expect(c.text, isNotEmpty);
  });

  testWidgets(
    'system pop while a run is active prompts, then leaves on confirm',
    (tester) async {
      final c = makeController(client: _BlockingClient().client)..sampleLen = 3;
      c.startRun();
      await pumpPushedRun(tester, c);

      // A system back gesture while generating must not pop the view silently - it
      // funnels through the same confirmation as the Back buttons.
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cancel active narration run?'), findsOneWidget);
      expect(find.byKey(const Key('editorHost')), findsNothing);
      expect(c.narrating, isTrue);

      // Deferring keeps the run on screen and generating.
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('Back'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cancel active narration run?'), findsNothing);
      expect(c.runStopped, isFalse);
      expect(find.byKey(const Key('runHeaderTitle')), findsOneWidget);

      // Confirming cancelRun stops generation and pops back to the editor.
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('Cancel Run'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.runStopped, isTrue);
      expect(find.byKey(const Key('runHeaderTitle')), findsNothing);
      expect(find.byKey(const Key('editorHost')), findsOneWidget);
    },
  );

  testWidgets('double-tap Back while running shows a single confirm dialog', (
    tester,
  ) async {
    final c = makeController(client: _BlockingClient().client)..sampleLen = 3;
    c.startRun();
    await pumpPushedRun(tester, c);

    // Two taps land before the first dialog is built; the re-entrancy guard
    // must not stack a second confirm. The second tap may already be covered
    // by the first dialog's barrier, so a miss is expected and harmless.
    await tester.tap(find.byKey(const Key('runBackButton')).first);
    await tester.tap(
      find.byKey(const Key('runBackButton')).first,
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Cancel active narration run?'), findsOneWidget);
    expect(c.narrating, isTrue);

    // Confirming once stops the run and pops; a stray second invocation is
    // already blocked, and the run is no longer active anyway.
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.text('Cancel Run'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.runStopped, isTrue);
    expect(find.byKey(const Key('runHeaderTitle')), findsNothing);
    expect(find.byKey(const Key('editorHost')), findsOneWidget);
  });

  testWidgets('Back on an idle run pops without a prompt', (tester) async {
    final fake = FakeTtsProvider();
    final c = makeController(client: fake.client);
    final text = c.text;
    c.sampleLen = 1;
    c.startRun();
    await pumpRun(tester, c);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('runBackButton')).first);
    await tester.pumpAndSettle();

    expect(find.text('Cancel active narration run?'), findsNothing);
    expect(c.text, text);
    expect(c.narrating, isFalse);
    expect(fake.callCount, 1);
  });

  testWidgets('the summary pill freezes the run parameters', (tester) async {
    final c = makeController(client: FakeTtsProvider().client)..sampleLen = 1;
    c.startRun();
    await pumpRun(tester, c);
    await tester.pump(const Duration(milliseconds: 50));

    final before = tester
        .widget<Text>(find.byKey(const Key('runSummaryPill')))
        .data;
    expect(before, contains('1 segment · '));

    // Later editor/settings changes must not leak into the frozen run pill.
    c.setVoice('changed-id', label: 'Different Voice');
    c.minWords = 100;
    await tester.pump();

    final after = tester
        .widget<Text>(find.byKey(const Key('runSummaryPill')))
        .data;
    expect(after, before);
  });

  testWidgets('renders under Cupertino on macOS without Material errors', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final c = makeController(client: FakeTtsProvider().client)..sampleLen = 1;
    c.startRun();
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(testApp(home: NarrationScreen(controller: c)));

    expect(find.text('Narrating: untitled.txt'), findsOneWidget);
    expect(find.byKey(const Key('runSummaryPill')), findsOneWidget);
    expect(find.byKey(const Key('runProgressBar')), findsOneWidget);
    expect(find.byKey(const Key('segStatus_completed_0')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 50));
    expect(c.runFinished, isTrue);
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });
}
