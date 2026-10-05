import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MenuItemButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/menu/linux_menu_bar.dart';
import 'package:tts_narrator/src/gui/platform/platform_detection.dart';
import 'package:tts_narrator/src/gui/theme/app_tokens.dart' show AppThemeMode;

import '../support/l10n_test_support.dart';
import '../support/run_setup_fixtures.dart' as fixtures;

/// A throwaway controller over a temp config dir, mirroring the macOS menu
/// test so the bar is exercised against a real loaded model.
Future<AppController> makeController() async {
  final dir = Directory.systemTemp.createTempSync('tts_linux_menu_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final configDir = '${dir.path}/cfg';
  fixtures.writeConfig(configDir, {
    'models': {
      'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
    },
    'defaults': {'fish': 'British Female Narrator'},
    'voices': {
      'fish': {'British Female Narrator': '89f41ea230034706881f85a8227d6ab9'},
    },
  });
  return AppController(loader: UserVoiceConfigLoader(configDir: configDir));
}

/// Pumps [LinuxMenuBar] under a [CupertinoApp] — deliberately *not* a
/// [MaterialApp] — because that is the app's real ancestor chain. It proves the
/// bar needs no Material locale to build, which is what lets it ship
/// accelerator labels instead of `MenuItemButton.shortcut` bindings.
Future<void> pumpBar(
  WidgetTester tester,
  AppController controller, {
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  final key = navigatorKey ?? GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    CupertinoApp(
      navigatorKey: key,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: LinuxMenuBar(
        controller: controller,
        navigatorKey: key,
        child: const SizedBox.expand(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens a top-level submenu by its bar label and waits for the panel animation.
Future<void> openMenu(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// The [MenuItemButton] wrapping [label], or null when the row is not a
/// menu item (a separator, or a nested submenu).
MenuItemButton? itemButton(WidgetTester tester, String label) {
  final items = find.ancestor(
    of: find.text(label),
    matching: find.byType(MenuItemButton),
  );
  return items.evaluate().isEmpty
      ? null
      : tester.widget<MenuItemButton>(items.first);
}

bool isEnabled(WidgetTester tester, String label) =>
    itemButton(tester, label)?.onPressed != null;

void main() {
  group('linux menu bar structure', () {
    testWidgets('renders the File, Edit and View menus', (tester) async {
      await pumpBar(tester, await makeController());

      expect(find.text('File'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
    });

    testWidgets('File lists the commands with their accelerators', (
      tester,
    ) async {
      await pumpBar(tester, await makeController());
      await openMenu(tester, 'File');

      for (final label in <String>[
        'Open Text…',
        'Output Folder…',
        'Narrate',
        'Clear',
        'Save',
        'Save As…',
        'Clean Up Segments…',
        'Quit',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
      // The accelerator is drawn as a trailing label rather than bound, so it
      // is visible text the test can assert on.
      expect(find.text(acceleratorLabel('Q')), findsOneWidget);
    });

    testWidgets('File has no Close item', (tester) async {
      await pumpBar(tester, await makeController());
      await openMenu(tester, 'File');

      // Close (⌘W / Ctrl+W) never closed anything — it called maybePop on the
      // root route, which is a no-op — so it is gone from both bars.
      expect(find.text('Close'), findsNothing);
    });

    testWidgets('Edit has undo/redo/cut/copy/paste/select all', (tester) async {
      await pumpBar(tester, await makeController());
      await openMenu(tester, 'Edit');

      for (final label in <String>[
        'Undo',
        'Redo',
        'Cut',
        'Copy',
        'Paste',
        'Select All',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
    });
  });

  group('linux menu bar disabled states', () {
    testWidgets('Narrate is disabled while the run is blocked', (tester) async {
      final controller = await makeController();
      await pumpBar(tester, controller);
      await openMenu(tester, 'File');

      // Empty document: narrateBlockReason() is non-null.
      expect(controller.narrateBlockReason(), isNotNull);
      expect(isEnabled(tester, 'Narrate'), isFalse);

      await tester.tapAt(Offset.zero); // dismiss the open panel
      await tester.pumpAndSettle();
      controller.setText('some words to narrate');
      await tester.pumpAndSettle();
      await openMenu(tester, 'File');

      expect(controller.narrateBlockReason(), isNull);
      expect(isEnabled(tester, 'Narrate'), isTrue);
    });

    testWidgets('Clear is disabled while the document is empty', (
      tester,
    ) async {
      final controller = await makeController();
      await pumpBar(tester, controller);
      await openMenu(tester, 'File');

      expect(isEnabled(tester, 'Clear'), isFalse);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      controller.setText('something');
      await tester.pumpAndSettle();
      await openMenu(tester, 'File');

      expect(isEnabled(tester, 'Clear'), isTrue);
    });

    testWidgets('Clean Up Segments is disabled before a run', (tester) async {
      final controller = await makeController();
      await pumpBar(tester, controller);
      await openMenu(tester, 'File');

      expect(controller.canCleanupSegments, isFalse);
      expect(isEnabled(tester, 'Clean Up Segments…'), isFalse);
    });
  });

  group('linux menu bar dispatch', () {
    testWidgets('Open Text… dispatches commands.onOpen', (tester) async {
      final controller = await makeController();
      var opened = 0;
      controller.commands.onOpen = () => opened++;
      await pumpBar(tester, controller);
      await openMenu(tester, 'File');

      await tester.tap(find.text('Open Text…'));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });

    testWidgets('Output Folder… dispatches commands.onSetOutputFolder', (
      tester,
    ) async {
      final controller = await makeController();
      var picked = 0;
      controller.commands.onSetOutputFolder = () => picked++;
      await pumpBar(tester, controller);
      await openMenu(tester, 'File');

      await tester.tap(find.text('Output Folder…'));
      await tester.pumpAndSettle();

      expect(picked, 1);
    });

    testWidgets('Toggle Run Setup Panel dispatches its command slot', (
      tester,
    ) async {
      final controller = await makeController();
      var toggled = 0;
      controller.commands.onToggleRunSetupPanel = () => toggled++;
      await pumpBar(tester, controller);
      await openMenu(tester, 'View');

      await tester.tap(find.text('Toggle Run Setup Panel'));
      await tester.pumpAndSettle();

      expect(toggled, 1);
    });
  });

  group('linux menu bar appearance', () {
    testWidgets('marks the active mode and applies a new one', (tester) async {
      final controller = await makeController()
        ..themeMode = AppThemeMode.dark;
      await pumpBar(tester, controller);
      await openMenu(tester, 'View');
      await openMenu(tester, 'Appearance');

      // MenuItemButton has no `checked` flag, so the active mode is marked
      // with the same leading checkmark the macOS bar uses.
      expect(find.text('✓ Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(controller.themeMode, AppThemeMode.light);
    });
  });
}
