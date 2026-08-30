import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/editor/editor_screen.dart';
import 'package:tts_narrator/src/gui/platform/widgets/platform_text_field.dart';

void main() {
  late Directory dir;
  late String configPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_editor_test_');
    configPath = '${dir.path}/voice_config.json';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<AppController> makeController() async {
    File(configPath).writeAsStringSync(const JsonEncoder().convert({}));
    return AppController(loader: VoiceConfigLoader(configPath: configPath));
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
    expect(find.textContaining('0 words · 0 chars'), findsOneWidget);
    expect(find.textContaining('0 chunks · 0.0 min · '), findsOneWidget);
    expect(find.byKey(const Key('editorOpenButton')), findsOneWidget);
    expect(find.byKey(const Key('editorNarrateButton')), findsOneWidget);
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
    await tester.pump();

    expect(find.textContaining('12 words · '), findsOneWidget);
    expect(find.textContaining('1 chunk'), findsOneWidget);
    expect(find.textContaining(r' · $0.00 (free)'), findsOneWidget);
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
  });

  testWidgets('Narrate on an empty document shows the guard banner', (
    tester,
  ) async {
    final controller = await makeController();
    await pumpEditor(tester, controller);

    await tester.tap(find.byKey(const Key('editorNarrateButton')));
    await tester.pump();

    expect(find.byKey(const Key('narrateGuard')), findsOneWidget);
    expect(find.textContaining('Nothing to narrate yet'), findsOneWidget);

    // The banner auto-dismisses after the guard timer.
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('narrateGuard')), findsNothing);
  });

  testWidgets('Narrate dispatch is a no-op until the run view lands', (
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
}