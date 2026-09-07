import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/editor/editor_status_bar.dart';
import 'package:tts_narrator/src/gui/theme/app_tokens.dart';

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_status_bar_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AppController makeController() =>
      AppController(loader: VoiceConfigLoader(configDir: configDir));

  Future<void> pumpStatusBar(
    WidgetTester tester,
    AppController controller, {
    Size size = const Size(1000, 800),
    Brightness brightness = Brightness.light,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: EditorStatusBar(controller: controller)),
      ),
    );
  }

  String statusOutDirText(WidgetTester tester) =>
      (tester.widget<Text>(find.byKey(const Key('statusOutDir'))).data)!;

  /// The [Text] style color for the named readout.
  Color readoutColor(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).style!.color!;

  testWidgets('boots with zeroed counts and the default output folder', (
    tester,
  ) async {
    final controller = makeController();
    await pumpStatusBar(tester, controller);

    expect(find.byKey(const Key('statusBar')), findsOneWidget);
    expect(find.textContaining('0 words · 0 characters'), findsOneWidget);
    expect(
      find.textContaining('0 segments · ~0 mins · ~\$0.00 (free) est.'),
      findsOneWidget,
    );
    expect(statusOutDirText(tester), 'output');
  });

  testWidgets('shows the full output folder path when it fits the slot', (
    tester,
  ) async {
    final controller = makeController();
    const longPath = '/deep/folder';
    controller.outDir = longPath;
    await pumpStatusBar(tester, controller);

    expect(statusOutDirText(tester), longPath);
  });

  testWidgets('left-truncates a long output folder path to fit the slot', (
    tester,
  ) async {
    final controller = makeController();
    const longPath =
        '/a/very/long/prefix/that/will/not/fit/in/any/window/width/finalLeaf';
    controller.outDir = longPath;
    await pumpStatusBar(tester, controller);

    final rendered = statusOutDirText(tester);
    // The leaf folder name survives the truncation.
    expect(rendered.endsWith('finalLeaf'), isTrue);
    // A leading ellipsis marks the truncation.
    expect(rendered.startsWith('\u2026'), isTrue);
    // The full path was shortened.
    expect(rendered.length, lessThan(longPath.length));
  });

  testWidgets('shows thousands separators for large counts', (tester) async {
    final controller = makeController();
    controller.setText(List.generate(1240, (i) => 'word').join(' '));
    await pumpStatusBar(tester, controller);

    expect(find.textContaining('1,240 words'), findsOneWidget);
  });

  testWidgets('repaints when the controller notifies', (tester) async {
    final controller = makeController();
    await pumpStatusBar(tester, controller);

    controller.setText(
      'The rain fell on the quiet street. Lights glowed behind the windows.',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('12 words · '), findsOneWidget);
    expect(find.textContaining('1 segment'), findsOneWidget);
  });

  testWidgets('anchors the estimate readout at the right edge of the bar', (
    tester,
  ) async {
    final controller = makeController();
    await pumpStatusBar(tester, controller);
    await tester.pumpAndSettle();

    final barRect = tester.getRect(find.byKey(const Key('statusBar')));
    final estimateRight = tester.getBottomRight(
      find.byKey(const Key('editorEstimate')),
    );
    // Bar padding 16px insets the text from the edge (no pill padding anymore).
    expect(estimateRight.dx, closeTo(barRect.right - 16, 1));
  });

  testWidgets('readouts use textSecondary at 75% in light mode', (tester) async {
    final controller = makeController();
    await pumpStatusBar(tester, controller);

    final expected = AppPalette.light.textSecondary.withValues(alpha: 0.75);
    expect(
      tester.widget<Text>(find.textContaining(' words · ')).style!.color,
      expected,
    );
    expect(readoutColor(tester, const Key('statusOutDir')), expected);
    expect(readoutColor(tester, const Key('editorEstimate')), expected);
  });

  testWidgets('readouts use textSecondary at 75% in dark mode', (tester) async {
    final controller = makeController();
    await pumpStatusBar(tester, controller, brightness: Brightness.dark);

    final expected = AppPalette.dark.textSecondary.withValues(alpha: 0.75);
    expect(
      tester.widget<Text>(find.textContaining(' words · ')).style!.color,
      expected,
    );
    expect(readoutColor(tester, const Key('statusOutDir')), expected);
    expect(readoutColor(tester, const Key('editorEstimate')), expected);
  });
}
