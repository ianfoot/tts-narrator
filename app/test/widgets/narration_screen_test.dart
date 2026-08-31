import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/narration/narration_screen.dart';
import 'package:tts_narrator/src/gui/platform/widgets/platform_list_tile.dart';
import '../support/fake_tts_provider.dart';

void main() {
  late Directory dir;
  late String configPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_narration_screen_');
    configPath = '${dir.path}/voice_config.json';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AppController makeController() {
    File(configPath).writeAsStringSync('{}');
    final c = AppController(loader: VoiceConfigLoader(configPath: configPath))
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

  testWidgets('a launched run renders the banner and chunk plan', (
    tester,
  ) async {
    final fake = FakeTtsProvider()..register();
    final c = makeController()..sampleLen = 1;
    c.startRun();
    await pumpRun(tester, c);

    expect(find.textContaining('Narrate — untitled.txt'), findsOneWidget);
    expect(find.byKey(const Key('runBannerModelVoice')), findsOneWidget);
    expect(find.textContaining('chunks · '), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(1));
    expect(find.byKey(const Key('runBackButton')), findsOneWidget);

    // Let the single chunk land; then Cancel disappears and chunks are done.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('runCancelButton')), findsNothing);
    expect(find.textContaining('Narration complete.'), findsOneWidget);
    expect(fake.callCount, 1);
    // Only the sampled count becomes chunks, so progress completes at 100%.
    expect(c.totalChunks, 1);
    expect(c.runDoneCount, 1);
    expect(c.runProgress, 1.0);
  });

  testWidgets('empty-text plan failure renders the plan-error banner', (
    tester,
  ) async {
    FakeTtsProvider().register();
    final c = AppController(loader: VoiceConfigLoader(configPath: configPath))
      ..outDir = dir.path;
    c.startRun();
    await pumpRun(tester, c);

    expect(find.textContaining('No paragraphs found'), findsOneWidget);
    expect(find.byKey(const Key('runCancelButton')), findsNothing);
  });

  testWidgets('per-chunk completion enables playback affordances', (
    tester,
  ) async {
    FakeTtsProvider().register();
    final c = makeController()..sampleLen = 2;
    c.startRun();
    await pumpRun(tester, c);

    await tester.pump(const Duration(milliseconds: 50));
    expect(c.runFinished, isTrue);
    expect(c.runDoneCount, 2);
    // Each done chunk's clip exists on disk -> play buttons present.
    expect(find.byType(IconButton), findsNWidgets(2));
    await tester.tap(find.byType(IconButton).first);
    await tester.pump();
    expect(find.byType(IconButton), findsNWidgets(2));
  });

  testWidgets('Cancel stops a running narration', (tester) async {
    // A provider that never returns keeps the run in-flight so Cancel is
    // meaningful; the abort token throws synchronously at the next checkpoint.
    FakeTtsProvider().register();
    final c = makeController()..sampleLen = 5;
    c.startRun();
    c.cancelRun();
    await pumpRun(tester, c);

    expect(find.textContaining('Narration was stopped.'), findsOneWidget);
    expect(find.byKey(const Key('runCancelButton')), findsNothing);
    // Back returns to the editor (pops on the hosting navigator in the app).
    expect(find.byKey(const Key('runBackButton')), findsOneWidget);
  });

testWidgets('Back preserves the document in the controller', (tester) async {
    final c = makeController();
    final text = c.text;
    final fake = FakeTtsProvider()..register();
    c.sampleLen = 1;
    c.startRun();
    await pumpRun(tester, c);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('runBackButton')));
    await tester.pumpAndSettle();

    expect(c.text, text);
    expect(c.narrating, isFalse);
    expect(fake.callCount, 1);
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

    // The macOS path must render the run with platform (Cupertino) tiles and
    // no Material-required widget crashing.
    expect(find.byKey(const Key('runBannerModelVoice')), findsOneWidget);
    expect(find.byType(PlatformListTile), findsNWidgets(1));
    expect(find.byKey(const Key('runProgressBar')), findsOneWidget);
    expect(find.byKey(const Key('runBackButton')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 50));
    expect(c.runFinished, isTrue);
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });
}