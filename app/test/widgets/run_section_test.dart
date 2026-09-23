import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart'
    show maxWholeFileLength;

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/settings/run_section.dart';

import '../support/settings_fixtures.dart';

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_run_section_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpSection(WidgetTester tester, AppController c) =>
      pumpSettingsSection(tester, RunSection(controller: c));

  testWidgets('the whole-file switch renders on by default off', (
    tester,
  ) async {
    writeConfig(configDir, {});
    final c = makeController(configDir);
    await pumpSection(tester, c);

    expect(c.sendWholeFile, isFalse);
    expect(find.byKey(const Key('wholeFileSwitch')), findsOneWidget);
    // Segmentation controls are visible while the switch is off.
    expect(find.byKey(const Key('minWordsSlider')), findsOneWidget);
    expect(find.byKey(const Key('minWordsBadge')), findsOneWidget);
  });

  testWidgets('enabling whole-file hides the min-words section', (
    tester,
  ) async {
    writeConfig(configDir, {});
    final c = makeController(configDir);
    await pumpSection(tester, c);

    await tester.tap(find.byKey(const Key('wholeFileSwitch')));
    await tester.pump();

    expect(c.sendWholeFile, isTrue);
    expect(find.byKey(const Key('minWordsSlider')), findsNothing);
    expect(find.byKey(const Key('minWordsBadge')), findsNothing);
    expect(find.byKey(const Key('sampleSwitch')), findsOneWidget);
    expect(find.byKey(const Key('resumeSwitch')), findsOneWidget);

    // Toggling back restores the slider with the preserved value.
    await tester.tap(find.byKey(const Key('wholeFileSwitch')));
    await tester.pump();
    expect(c.sendWholeFile, isFalse);
    expect(find.byKey(const Key('minWordsSlider')), findsOneWidget);
    expect(find.byKey(const Key('minWordsBadge')), findsOneWidget);
  });

  testWidgets('documents over 60k chars hide the whole-file toggle', (
    tester,
  ) async {
    writeConfig(configDir, {});
    final c = makeController(configDir);
    c.setText(List.filled(maxWholeFileLength + 1, 'x').join());
    await pumpSection(tester, c);

    expect(c.wholeFileAvailable, isFalse);
    expect(find.byKey(const Key('wholeFileSwitch')), findsNothing);
    // The segment plan remains available; only whole-file is out of reach.
    expect(find.byKey(const Key('minWordsSlider')), findsOneWidget);
  });

  testWidgets('the min-words slider updates the controller within 10-100', (
    tester,
  ) async {
    writeConfig(configDir, {});
    final c = makeController(configDir);
    await pumpSection(tester, c);

    expect(c.minWords, 30);
    // Drag to the far right -> 100.
    await tester.drag(
      find.byKey(const Key('minWordsSlider')),
      const Offset(600, 0),
    );
    await tester.pump();
    expect(c.minWords, 100);

    // Drag to the far left -> 10 (the slider's minimum).
    await tester.drag(
      find.byKey(const Key('minWordsSlider')),
      const Offset(-600, 0),
    );
    await tester.pump();
    expect(c.minWords, 10);
  });

  testWidgets('sample mode toggles the inline segment count input', (
    tester,
  ) async {
    writeConfig(configDir, {});
    final c = makeController(configDir);
    await pumpSection(tester, c);

    expect(find.byKey(const Key('sampleLenField')), findsNothing);

    await tester.tap(find.byKey(const Key('sampleSwitch')));
    await tester.pump();
    expect(c.sampleLen, 1);
    expect(find.byKey(const Key('sampleLenField')), findsOneWidget);
    expect(find.text('Narrate first segments only'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('sampleLenField')),
        matching: find.byType(TextField),
      ),
      '3',
    );
    await tester.pump();
    expect(c.sampleLen, 3);

    await tester.tap(find.byKey(const Key('sampleSwitch')));
    await tester.pump();
    expect(c.sampleLen, isNull);
    expect(find.byKey(const Key('sampleLenField')), findsNothing);
  });

  testWidgets('clearing the sample count keeps sample mode on', (tester) async {
    writeConfig(configDir, {});
    final c = makeController(configDir);
    await pumpSection(tester, c);

    await tester.tap(find.byKey(const Key('sampleSwitch')));
    await tester.pump();
    expect(c.sampleLen, 1);

    final field = find.descendant(
      of: find.byKey(const Key('sampleLenField')),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '');
    await tester.pump();
    expect(c.sampleLen, 1);
    expect(find.byKey(const Key('sampleLenField')), findsOneWidget);

    await tester.enterText(field, '7');
    await tester.pump();
    expect(c.sampleLen, 7);
  });

  testWidgets('the resume switch writes through', (tester) async {
    writeConfig(configDir, {});
    final c = makeController(configDir);
    await pumpSection(tester, c);

    await tester.tap(find.byKey(const Key('resumeSwitch')));
    await tester.pump();

    expect(c.resume, isTrue);
  });
}
