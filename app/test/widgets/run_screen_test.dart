import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'package:tts_narrator/src/gui/run_screen.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('tts_run_test_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('dry-run shows the plan and cost without narrating', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final input = File('${dir.path}/story.txt')
      ..writeAsStringSync(
        'The rain fell on the quiet street. '
        'Lights glowed behind the windows of every house. '
        'It was an evening of small, patient sounds.',
      );

    final config = NarrationConfig(
      inputPath: input.path,
      profile: kFishProfile,
      voice: kFishProfile.defaultVoice,
    );

    await tester.pumpWidget(MaterialApp(home: RunScreen(config: config)));

    expect(find.byType(RunScreen), findsOneWidget);
    expect(find.textContaining(r'$0.00 (free)'), findsOneWidget);
    expect(find.textContaining('Model: fish'), findsOneWidget);
    expect(find.textContaining('Chunks:'), findsOneWidget);
    expect(find.byKey(const Key('startNarrationButton')), findsOneWidget);
    expect(find.text('Narrate'), findsOneWidget);
  });

  testWidgets('shows a plan error when the input file is missing', (
    tester,
  ) async {
    final config = NarrationConfig(
      inputPath: '${dir.path}/missing.txt',
      profile: kGeminiProfile,
      voice: kGeminiProfile.defaultVoice,
    );

    await tester.pumpWidget(MaterialApp(home: RunScreen(config: config)));

    expect(find.textContaining('Plan failed'), findsOneWidget);
  });
}