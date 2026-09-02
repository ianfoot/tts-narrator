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
import 'package:tts_narrator/src/gui/settings/inspector_rail.dart';

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

  Future<void> pumpEditor(WidgetTester tester, AppController controller) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: controller)),
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
    expect(find.text('⌘O'), findsOneWidget);
    expect(find.text('⌘N'), findsOneWidget);
  });

  testWidgets('the settings rail is visible by default and toggles away', (
    tester,
  ) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);

    expect(find.byType(InspectorRail), findsOneWidget);

    await tester.tap(find.byKey(const Key('railToggleButton')));
    await tester.pumpAndSettle();
    expect(find.byType(InspectorRail), findsNothing);

    await tester.tap(find.byKey(const Key('railToggleButton')));
    await tester.pumpAndSettle();
    expect(find.byType(InspectorRail), findsOneWidget);
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

  testWidgets('the rail close button hides the rail', (tester) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);

    await tester.tap(find.byKey(const Key('railCloseButton')));
    await tester.pumpAndSettle();
    expect(find.byType(InspectorRail), findsNothing);
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

  testWidgets('status bar shows thousands separators for large counts', (
    tester,
  ) async {
    final controller = await makeController();
    controller.setText(List.generate(1240, (i) => 'word').join(' '));
    await pumpEditor(tester, controller);

    expect(find.textContaining('1,240 words'), findsOneWidget);
  });
}