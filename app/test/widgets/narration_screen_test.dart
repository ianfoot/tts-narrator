import 'dart:async';
import 'dart:io';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/narration/narration_screen.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';
import '../support/fake_tts_provider.dart';

/// Deterministic audioplayers platform for widget tests: every player is a
/// local [StreamController] the test can emit into (prepared is sent
/// automatically on [setSourceUrl]; completion is driven by the test to verify
/// the Play/Stop auto-revert). The real method/event channels never run.
class _FakeAudioPlatform extends AudioplayersPlatformInterface {
  final Map<String, StreamController<AudioEvent>> _streams = {};
  final List<StreamController<AudioEvent>> _creationOrder = [];

  /// The stream of the most recently created player (the screen uses one).
  StreamController<AudioEvent> get lastStream => _creationOrder.last;

  void emitComplete() {
    lastStream.add(const AudioEvent(eventType: AudioEventType.complete));
  }

  @override
  Future<void> create(String playerId) async {
    final stream = StreamController<AudioEvent>.broadcast();
    _streams[playerId] = stream;
    _creationOrder.add(stream);
  }

  @override
  Future<void> dispose(String playerId) async {
    await _streams.remove(playerId)?.close();
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) => _streams[playerId]!.stream;

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    _streams[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {}

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> resume(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> seek(String playerId, Duration position) async {}

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}

  @override
  Future<void> setAudioContext(String playerId, AudioContext audioContext) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<int?> getDuration(String playerId) async => null;

  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}
}

/// Global (all-players) audio scope fake: makes the per-player `AudioPlayer`
/// constructor's global init resolve without a platform channel.
class _FakeGlobalAudioPlatform extends GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}

  @override
  Future<void> setGlobalAudioContext(AudioContext context) async {}

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Future<void> emitGlobalError(String code, String message) async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() =>
      const Stream<GlobalAudioEvent>.empty();
}

/// Provider whose [synthesize] never returns: keeps a run in-flight so Cancel
/// and the active-run Back confirm modal are meaningful.
class _BlockingProvider implements TtsProvider {
  @override
  String get id => 'openrouter';

  @override
  String get name => 'Blocking TTS';

  @override
  ModelUiSpec modelUiSpecFor(TtsModelProfile model) =>
      const ModelUiSpec.empty();

  @override
  Future<ProviderAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
    AbortToken? abort,
  }) async {
    await Completer<void>().future;
    abort?.throwIfCancelled();
    return ProviderAudio(bytes: const [0]);
  }

  void register() => ttsProviderRegistry.register('openrouter', () => this);
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

  AppController makeController() {
    File('$configDir/config.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');
    final c = AppController(loader: VoiceConfigLoader(configDir: configDir))
      ..outDir = dir.path;
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
      MaterialApp(home: NarrationScreen(controller: controller)),
    );
  }

  /// Pumps the run view as a *pushed* route above an editor placeholder so a
  /// confirmed Back actually pops the view (the `home:` variant cannot pop).
  Future<void> pumpPushedRun(WidgetTester tester, AppController controller) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: Text('EDITOR', key: const Key('editorHost'))),
          ),
        ),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => NarrationScreen(controller: controller)),
    );
    // Fixed pumps, not pumpAndSettle: an active run renders an ever-animating
    // spinner that would never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('a launched run renders the header and frozen summary pill', (
    tester,
  ) async {
    final fake = FakeTtsProvider()..register();
    final c = makeController()..sampleLen = 1;
    c.startRun();
    await pumpRun(tester, c);

    expect(find.text('Narrating: untitled.txt'), findsOneWidget);
    expect(find.byKey(const Key('runHeaderTitle')), findsOneWidget);
    final pill = tester.widget<Text>(find.byKey(const Key('runSummaryPill')));
    expect(pill.data, contains('segments · '));
    expect(pill.data, contains('·'));
    expect(find.byKey(const Key('runProgressBar')), findsOneWidget);
    expect(find.byKey(const Key('runBackButton')), findsOneWidget);
    expect(find.byKey(const Key('runActionBack')), findsOneWidget);

    // Let the single chunk land; then Cancel disappears and chunks are done.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('runCancelButton')), findsNothing);
    expect(find.textContaining('Narration complete.'), findsOneWidget);
    expect(fake.callCount, 1);
    expect(c.totalChunks, 1);
    expect(c.runDoneCount, 1);
    expect(c.runProgress, 1.0);
    expect(find.byKey(const Key('segStatus_completed_0')), findsOneWidget);
    expect(find.byKey(const Key('segAction_0')), findsOneWidget);
    expect(find.text('Segment 1'), findsOneWidget);
  });

  testWidgets('empty-text plan failure renders the plan-error banner', (
    tester,
  ) async {
    FakeTtsProvider().register();
    final c = AppController(loader: VoiceConfigLoader(configDir: configDir))
      ..outDir = dir.path;
    c.startRun();
    await pumpRun(tester, c);

    expect(find.textContaining('No paragraphs found'), findsOneWidget);
    expect(find.byKey(const Key('runCancelButton')), findsNothing);
  });

  testWidgets('segment cards render all four status states in 3 columns', (
    tester,
  ) async {
    FakeTtsProvider().register();
    final c = makeController()..sampleLen = 2;
    c.startRun();
    await pumpRun(tester, c);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.runFinished, isTrue);

    // Recast the two real chunks plus two synthetic ones to cover every state.
    c.runChunks[0].filePath = null; // pending
    // chunk 1 stays completed (its clip landed on disk during the run).
    final resumedFile = File('${dir.path}/resumed.wav')
      ..writeAsStringSync('x');
    c.runChunks.addAll([
      NarrationRunChunk(index: 2, paragraph: 'A third passage is processing.')
        ..running = true,
      NarrationRunChunk(index: 3, paragraph: 'A reused fourth passage.')
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
    final original = AudioplayersPlatformInterface.instance;
    final originalGlobal = GlobalAudioplayersPlatformInterface.instance;
    final audio = _FakeAudioPlatform();
    AudioplayersPlatformInterface.instance = audio;
    GlobalAudioplayersPlatformInterface.instance = _FakeGlobalAudioPlatform();
    addTearDown(() {
      AudioplayersPlatformInterface.instance = original;
      GlobalAudioplayersPlatformInterface.instance = originalGlobal;
    });
    FakeTtsProvider().register();
    final c = makeController()..sampleLen = 1;
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
    _BlockingProvider().register();
    final c = makeController()..sampleLen = 5;
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
    _BlockingProvider().register();
    final c = makeController()..sampleLen = 3;
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
        of: find.byType(AlertDialog),
        matching: find.text('Back'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Cancel active narration run?'), findsNothing);
    expect(c.narrating, isTrue);

    // Retry and confirm with "Cancel Run": the run stops and the view pops.
    await tester.tap(find.byKey(const Key('runBackButton')).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
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

  testWidgets('system pop while a run is active prompts, then leaves on confirm', (
    tester,
  ) async {
    _BlockingProvider().register();
    final c = makeController()..sampleLen = 3;
    c.startRun();
    await pumpPushedRun(tester, c);

    // A system back (macOS ⌘W / Close menu) while generating must not pop the
    // view silently - it funnels through the same confirmation.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Cancel active narration run?'), findsOneWidget);
    expect(find.byKey(const Key('editorHost')), findsNothing);
    expect(c.narrating, isTrue);

    // Deferring keeps the run on screen and generating.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
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
        of: find.byType(AlertDialog),
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

  testWidgets('double-tap Back while running shows a single confirm dialog', (
    tester,
  ) async {
    _BlockingProvider().register();
    final c = makeController()..sampleLen = 3;
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
        of: find.byType(AlertDialog),
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
    final c = makeController();
    final text = c.text;
    final fake = FakeTtsProvider()..register();
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
    FakeTtsProvider().register();
    final c = makeController()..sampleLen = 1;
    c.startRun();
    await pumpRun(tester, c);
    await tester.pump(const Duration(milliseconds: 50));

    final before = tester
        .widget<Text>(find.byKey(const Key('runSummaryPill')))
        .data;
    expect(before, contains('segments · '));

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
    FakeTtsProvider().register();
    final c = makeController()..sampleLen = 1;
    c.startRun();
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(CupertinoApp(home: NarrationScreen(controller: c)));

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