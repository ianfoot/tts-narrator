import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/config/config_screen.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../support/l10n_test_support.dart';
import '../support/settings_fixtures.dart' as fixtures;

/// Widget tests for the providers & voices screen.
///
/// The screen is the app's only writer for the config directory, so these
/// cases assert against what actually landed on disk as well as what the table
/// shows: a row that appears in the picker is only useful if the overlay file
/// behind it is well formed.
void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_config_screen_test_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// An open model (`voices_editable`) with two named voices, the shape the
  /// shipped fish config uses.
  void writeEditableConfig() {
    fixtures.writeConfig(configDir, {
      'models': {
        'fish': {
          'id': 'fish-audio/s2.1-pro-free:free',
          'format': 'mp3',
          'display_name': 'Fish Audio S2.1 (Free)',
          'voices_editable': true,
        },
      },
      'defaults': {'fish': 'British Female Narrator'},
      'voices': {
        'fish': {
          'British Female Narrator': '89f41ea230034706881f85a8227d6ab9',
          'Alice': 'c536c6cdbe8e4d9484232e78ab80020f',
        },
      },
    });
  }

  /// The same config with the editability flag absent, as a model whose voice
  /// list is fixed by its provider ships.
  void writeLockedConfig() {
    fixtures.writeConfig(configDir, {
      'models': {
        'kokoro': {'id': 'hexgrad/kokoro-82m', 'format': 'mp3'},
      },
      'defaults': {'kokoro': 'bf_emma'},
      'voices': {
        'kokoro': {'bf_emma': 'bf_emma'},
      },
    });
  }

  AppController makeController() => fixtures.makeController(configDir);

  Future<void> pumpConfigScreen(WidgetTester tester, AppController c) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      testApp(home: ConfigScreen(controller: c)),
    );
    await tester.pumpAndSettle();
  }

  group('layout', () {
    testWidgets('shows the model metadata and every configured voice', (
      tester,
    ) async {
      writeEditableConfig();
      await pumpConfigScreen(tester, makeController());

      expect(find.text('Providers & Voices'), findsOneWidget);
      // The metadata section header is upper-cased by AppSection; the model list
      // row beside it keeps the display name and appends the alias, so the two
      // are told apart here by more than a substring.
      expect(find.text('FISH AUDIO S2.1 (FREE)'), findsOneWidget);
      expect(
        find.text('Fish Audio S2.1 (Free) · fish'),
        findsOneWidget,
        reason: 'the list row names the display name and the alias behind it',
      );
      expect(find.text('fish-audio/s2.1-pro-free:free'), findsOneWidget);
      expect(find.text('Label'), findsOneWidget);
      expect(find.text('Voice ID'), findsOneWidget);
      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('British Female Narrator'), findsOneWidget);
      expect(find.text('89f41ea230034706881f85a8227d6ab9'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('c536c6cdbe8e4d9484232e78ab80020f'), findsOneWidget);
    });

    testWidgets('an empty config says so instead of rendering an empty pane', (
      tester,
    ) async {
      fixtures.writeConfig(configDir, {
        'models': <String, Object?>{},
      });
      await pumpConfigScreen(tester, makeController());

      // Both panes say it: the list has nothing to list, and the editor pane
      // has no model to show. Two is the point — one message in a pane that
      // otherwise renders blank reads as a broken layout.
      expect(
        find.textContaining('No models configured'),
        findsNWidgets(2),
      );
    });
  });

  group('editing', () {
    testWidgets('a locked model offers no add affordance and explains why', (
      tester,
    ) async {
      writeLockedConfig();
      await pumpConfigScreen(tester, makeController());

      expect(find.byKey(const Key('addVoiceButton')), findsNothing);
      expect(find.textContaining('voice list is fixed'), findsOneWidget);
      // The rows are still readable — locked means read-only, not hidden.
      expect(find.text('bf_emma'), findsWidgets);
    });

    testWidgets('an open model can add a voice, which lands in the overlay', (
      tester,
    ) async {
      writeEditableConfig();
      final c = makeController();
      await pumpConfigScreen(tester, c);

      await tester.tap(find.byKey(const Key('addVoiceButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('voiceDialogLabelField')),
        'Custom',
      );
      await tester.enterText(
        find.byKey(const Key('voiceDialogIdField')),
        'deadbeef',
      );
      await tester.tap(find.byKey(const Key('voiceDialogSaveButton')));
      await tester.pumpAndSettle();

      // The new row shows...
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('deadbeef'), findsOneWidget);
      // ...it reached the disk, in the overlay and not the downloaded file...
      final overlay = VoiceConfigStore(configDir);
      expect(overlay.hasOverlayModel('fish'), isTrue);
      expect(
        overlay.readModelJson('fish')!['voices'],
        containsPair('Custom', {'id': 'deadbeef'}),
      );
      // ...and the controller re-read it, so the picker has it too.
      expect(c.voiceItems.where((i) => i.$1 == 'deadbeef'), hasLength(1));
    });

    testWidgets('a cancelled dialog writes nothing', (tester) async {
      writeEditableConfig();
      await pumpConfigScreen(tester, makeController());

      await tester.tap(find.byKey(const Key('addVoiceButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('voiceDialogIdField')),
        'deadbeef',
      );
      await tester.tap(find.byKey(const Key('voiceDialogCancelButton')));
      await tester.pumpAndSettle();

      expect(VoiceConfigStore(configDir).hasOverlayModel('fish'), isFalse);
    });

    testWidgets('a blank row is refused and no file is written', (tester) async {
      writeEditableConfig();
      await pumpConfigScreen(tester, makeController());

      await tester.tap(find.byKey(const Key('addVoiceButton')));
      await tester.pumpAndSettle();
      // Both fields blank: the dialog's submit is a no-op, so it stays open.
      await tester.tap(find.byKey(const Key('voiceDialogSaveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('voiceDialogLabelField')), findsOneWidget);
      expect(VoiceConfigStore(configDir).hasOverlayModel('fish'), isFalse);
    });

    testWidgets('removing the default voice is refused with a reason', (
      tester,
    ) async {
      writeEditableConfig();
      await pumpConfigScreen(tester, makeController());

      await tester.tap(
        find.byKey(
          const Key('removeVoice_89f41ea230034706881f85a8227d6ab9'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('voiceTableError')), findsOneWidget);
      expect(
        find.textContaining('default voice', findRichText: true),
        findsWidgets,
      );
      // Nothing was written, so the row is still there.
      expect(find.text('British Female Narrator'), findsOneWidget);
      expect(VoiceConfigStore(configDir).hasOverlayModel('fish'), isFalse);
    });

    testWidgets('a non-default voice can be removed', (tester) async {
      writeEditableConfig();
      await pumpConfigScreen(tester, makeController());

      await tester.tap(
        find.byKey(
          const Key('removeVoice_c536c6cdbe8e4d9484232e78ab80020f'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsNothing);
      expect(
        VoiceConfigStore(configDir).readModelJson('fish')!['voices'],
        isNot(contains('Alice')),
      );
      // The default the removed row was not is untouched.
      expect(
        VoiceConfigStore(
          configDir,
        ).readModelJson('fish')!['default_voice'],
        'British Female Narrator',
      );
    });

    testWidgets('renaming a voice carries the default across', (tester) async {
      writeEditableConfig();
      await pumpConfigScreen(tester, makeController());

      await tester.tap(
        find.byKey(
          const Key('editVoice_89f41ea230034706881f85a8227d6ab9'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('voiceDialogLabelField')),
        'Renamed Narrator',
      );
      await tester.tap(find.byKey(const Key('voiceDialogSaveButton')));
      await tester.pumpAndSettle();

      final json = VoiceConfigStore(configDir).readModelJson('fish')!;
      expect(json['default_voice'], 'Renamed Narrator');
      expect(find.text('Renamed Narrator'), findsOneWidget);
      expect(find.text('British Female Narrator'), findsNothing);
    });

    testWidgets('promoting another voice moves the default off it', (
      tester,
    ) async {
      writeEditableConfig();
      await pumpConfigScreen(tester, makeController());

      await tester.tap(
        find.byKey(
          const Key('defaultVoiceMark_c536c6cdbe8e4d9484232e78ab80020f'),
        ),
      );
      await tester.pumpAndSettle();

      final json = VoiceConfigStore(configDir).readModelJson('fish')!;
      expect(json['default_voice'], 'Alice');
    });
  });

  group('overlay state', () {
    testWidgets('an untouched model shows no revert control', (tester) async {
      writeEditableConfig();
      await pumpConfigScreen(tester, makeController());

      expect(find.byKey(const Key('revertModelButton')), findsNothing);
    });

    testWidgets('revert discards the override and restores the download', (
      tester,
    ) async {
      writeEditableConfig();
      final c = makeController();
      await pumpConfigScreen(tester, c);

      await tester.tap(find.byKey(const Key('addVoiceButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('voiceDialogLabelField')),
        'Custom',
      );
      await tester.enterText(
        find.byKey(const Key('voiceDialogIdField')),
        'deadbeef',
      );
      await tester.tap(find.byKey(const Key('voiceDialogSaveButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('revertModelButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('revertModelButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('revertModelButton')), findsNothing);
      expect(find.text('Custom'), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
      expect(
        VoiceConfigStore(configDir).hasOverlayModel('fish'),
        isFalse,
      );
      expect(c.voiceItems.where((i) => i.$1 == 'deadbeef'), isEmpty);
    });
  });
}
