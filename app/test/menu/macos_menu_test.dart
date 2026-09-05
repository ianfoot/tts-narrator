import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/menu/edit_actions.dart';
import 'package:tts_narrator/src/gui/menu/macos_menu.dart';
import 'package:tts_narrator/src/gui/theme/app_tokens.dart' show AppThemeMode;

import '../support/recording_cleanup_controller.dart';

Future<AppController> makeController() async {
  final dir = Directory.systemTemp.createTempSync('tts_menu_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final configDir = '${dir.path}/cfg';
  File('$configDir/config.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder().convert({}));
  return AppController(loader: VoiceConfigLoader(configDir: configDir));
}

/// The leaf items of [menu], expanding [PlatformMenuItemGroup] members and
/// recursing into submenus ([PlatformMenu]) so grouped commands (Preferences,
/// Close, the Edit group, the Appearance submenu) appear alongside the
/// standalone ones.
List<PlatformMenuItem> leafItems(PlatformMenu menu) => <PlatformMenuItem>[
  for (final item in menu.menus) ...leafChildren(item),
];

Iterable<PlatformMenuItem> leafChildren(PlatformMenuItem item) sync* {
  if (item is PlatformMenuItemGroup) {
    for (final member in item.members) {
      yield* leafChildren(member);
    }
  } else if (item is PlatformMenu) {
    for (final child in item.menus) {
      yield* leafChildren(child);
    }
  } else {
    yield item;
  }
}

PlatformMenuItem leafItem(PlatformMenu menu, String label) =>
    leafItems(menu).firstWhere((m) => bareLabel(m) == label);

/// The bare command label, stripping the leading checkmark prefix used to mark
/// the active Appearance mode.
String bareLabel(PlatformMenuItem item) {
  final label = item.label;
  return label.startsWith('✓ ') ? label.substring(2) : label;
}

/// Asserts [item] has a ⌘[key] shortcut (or ⇧⌘[key] when [shift]).
void expectMetaShortcut(
  PlatformMenuItem item,
  LogicalKeyboardKey key, {
  bool shift = false,
}) {
  final a = item.shortcut! as SingleActivator;
  expect(a.trigger, key);
  expect(a.meta, isTrue);
  expect(a.shift, shift);
}

/// Pumps a focused [TextField] and returns its controller, so the Edit menu
/// dispatch tests exercise the same focused-text-field path the app uses.
Future<TextEditingController> pumpFocusedField(WidgetTester tester) async {
  final controller = TextEditingController(text: 'one two three');
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ),
  );
  await tester.tap(find.byType(TextField));
  await tester.pump();
  return controller;
}

void main() {
  setUp(() {
    // The test harness does not mock the clipboard platform channel, so cuts
    // and pastes would hang on Clipboard.getData. Stub the methods the edit
    // actions use.
    final mockClipboard = <String, String>{};
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              mockClipboard['text'] = (call.arguments as Map)['text'] as String;
              return null;
            case 'Clipboard.getData':
              return {'text': mockClipboard['text']};
            case 'Clipboard.hasStrings':
              return {'value': mockClipboard['text'] != null};
          }
          return null;
        });
  });

  group('menu structure', () {
    test('top-level menus are App, File, Edit, View, Window', () async {
      final menus = buildMacMenu(
        controller: await makeController(),
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      expect(menus.map((m) => m.label).toList(), [
        'TTS Narrator',
        'File',
        'Edit',
        'View',
        'Window',
      ]);
    });

    test(
      'File has Open, Narrate, Save and Close with their shortcuts',
      () async {
        final file = buildMacMenu(
          controller: await makeController(),
          navigatorKey: GlobalKey<NavigatorState>(),
        )[1];

        expectMetaShortcut(
          leafItem(file, 'Open Text…'),
          LogicalKeyboardKey.keyO,
        );
        expectMetaShortcut(
          leafItem(file, 'Output Folder…'),
          LogicalKeyboardKey.keyE,
        );
        expectMetaShortcut(leafItem(file, 'Narrate'), LogicalKeyboardKey.keyN);
        expectMetaShortcut(leafItem(file, 'Save'), LogicalKeyboardKey.keyS);
        expectMetaShortcut(
          leafItem(file, 'Save As…'),
          LogicalKeyboardKey.keyS,
          shift: true,
        );
        expect(
          leafItem(file, 'Clean Up Segments…').label,
          'Clean Up Segments…',
        );
        expectMetaShortcut(leafItem(file, 'Close'), LogicalKeyboardKey.keyW);
      },
    );

    test(
      'Edit has undo/redo/cut/copy/paste/select all with shortcuts',
      () async {
        final edit = buildMacMenu(
          controller: await makeController(),
          navigatorKey: GlobalKey<NavigatorState>(),
        )[2];

        expectMetaShortcut(leafItem(edit, 'Undo'), LogicalKeyboardKey.keyZ);
        expectMetaShortcut(
          leafItem(edit, 'Redo'),
          LogicalKeyboardKey.keyZ,
          shift: true,
        );
        expectMetaShortcut(leafItem(edit, 'Cut'), LogicalKeyboardKey.keyX);
        expectMetaShortcut(leafItem(edit, 'Copy'), LogicalKeyboardKey.keyC);
        expectMetaShortcut(leafItem(edit, 'Paste'), LogicalKeyboardKey.keyV);
        expectMetaShortcut(
          leafItem(edit, 'Select All'),
          LogicalKeyboardKey.keyA,
        );
      },
    );

    test('App, View and Window carry the platform-provided items', () async {
      final menus = buildMacMenu(
        controller: await makeController(),
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      final app = menus[0];
      final view = menus[3];
      final window = menus[4];

      final provided = leafItems(app)
          .whereType<PlatformProvidedMenuItem>()
          .map((m) => m.type);
      expect(
        provided,
        containsAll(<PlatformProvidedMenuItemType>[
          PlatformProvidedMenuItemType.about,
          PlatformProvidedMenuItemType.quit,
        ]),
      );
      expect(leafItems(app).any((m) => m.label == 'Preferences…'), isTrue);

      final viewProvided =
          leafItems(view).whereType<PlatformProvidedMenuItem>().map((m) => m.type);
      expect(viewProvided, <PlatformProvidedMenuItemType>[
        PlatformProvidedMenuItemType.toggleFullScreen,
      ]);

      expect(
        window.menus.whereType<PlatformProvidedMenuItem>().map((m) => m.type),
        containsAll(<PlatformProvidedMenuItemType>[
          PlatformProvidedMenuItemType.minimizeWindow,
          PlatformProvidedMenuItemType.zoomWindow,
          PlatformProvidedMenuItemType.arrangeWindowsInFront,
        ]),
      );
    });
  });

  group('dispatch through controller slots', () {
    test('Narrate guards empty text and does not dispatch', () async {
      final controller = await makeController();
      var narrated = false;
      controller.onNarrate = () => narrated = true;
      final file = buildMacMenu(
        controller: controller,
        navigatorKey: GlobalKey<NavigatorState>(),
      )[1];

      leafItem(file, 'Narrate').onSelected?.call();
      expect(narrated, isFalse);
    });

    test('Narrate dispatches when text is present', () async {
      final controller = await makeController();
      controller.setText('Some real text to narrate.');
      var narrated = false;
      controller.onNarrate = () => narrated = true;
      final file = buildMacMenu(
        controller: controller,
        navigatorKey: GlobalKey<NavigatorState>(),
      )[1];

      leafItem(file, 'Narrate').onSelected?.call();
      expect(narrated, isTrue);
    });

    test('Open Text dispatches through the onOpen slot', () async {
      final controller = await makeController();
      var opened = false;
      controller.onOpen = () => opened = true;
      final file = buildMacMenu(
        controller: controller,
        navigatorKey: GlobalKey<NavigatorState>(),
      )[1];

      leafItem(file, 'Open Text…').onSelected?.call();
      expect(opened, isTrue);
    });

    test(
      'Output Folder dispatches through the onSetOutputFolder slot',
      () async {
        final controller = await makeController();
        var picked = false;
        controller.onSetOutputFolder = () => picked = true;
        final file = buildMacMenu(
          controller: controller,
          navigatorKey: GlobalKey<NavigatorState>(),
        )[1];

        leafItem(file, 'Output Folder…').onSelected?.call();
        expect(picked, isTrue);
      },
    );

test('Preferences dispatches through the onPreferences slot', () async {
      final controller = await makeController();
      var opened = false;
      controller.onPreferences = () => opened = true;
      final app = buildMacMenu(
        controller: controller,
        navigatorKey: GlobalKey<NavigatorState>(),
      )[0];


      leafItem(app, 'Preferences…').onSelected?.call();
      expect(opened, isTrue);
    });

    test('Save writes the document through the save flow', () async {
      final controller = await makeController();
      controller.setText('Body text worth keeping.');
      final tmp = Directory.systemTemp.createTempSync('tts_menu_save_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      controller.saveLocationPicker = () async => '${tmp.path}/doc.txt';

      final file = buildMacMenu(
        controller: controller,
        navigatorKey: GlobalKey<NavigatorState>(),
      )[1];
      leafItem(file, 'Save').onSelected?.call();
      await Future<void>.delayed(Duration.zero);

      expect(File('${tmp.path}/doc.txt').existsSync(), isTrue);
      expect(controller.dirty, isFalse);
    });

    test('Clean Up Segments is a no-op before any run', () async {
      final controller = RecordingCleanupController()
        ..overrideCleanup = () async {
          // Should never run: the guard returns first.
          fail('cleanup ran before any run');
        };
      final file = buildMacMenu(
        controller: controller,
        navigatorKey: GlobalKey<NavigatorState>(),
      )[1];

      expect(controller.cleanups, 0);
      leafItem(file, 'Clean Up Segments…').onSelected?.call();
      expect(controller.cleanups, 0);
    });
  });

  group('View menu commands', () {
    test('View has an Appearance submenu and a Toggle Settings Panel item',
        () async {
      final view = buildMacMenu(
        controller: await makeController(),
        navigatorKey: GlobalKey<NavigatorState>(),
      )[3];

      final appearance = view.menus
          .whereType<PlatformMenuItemGroup>()
          .single
          .members
          .whereType<PlatformMenu>()
          .single;
      // Defaults to the system mode, so Auto carries the checkmark prefix but
      // the bare labels stay Auto/Light/Dark.
      expect(appearance.menus.map(bareLabel).toList(), [
        'Auto',
        'Light',
        'Dark',
      ]);
      expectMetaShortcut(
        leafItem(view, 'Toggle Settings Panel'),
        LogicalKeyboardKey.backslash,
      );
    });

    test('Appearance items set the theme mode', () async {
      final controller = await makeController();
      final view = buildMacMenu(
        controller: controller,
        navigatorKey: GlobalKey<NavigatorState>(),
      )[3];

      leafItem(view, 'Light').onSelected?.call();
      expect(controller.themeMode, AppThemeMode.light);

      leafItem(view, 'Dark').onSelected?.call();
      expect(controller.themeMode, AppThemeMode.dark);

      leafItem(view, 'Auto').onSelected?.call();
      expect(controller.themeMode, AppThemeMode.system);
    });

    test('the active Appearance item carries a checkmark prefix', () async {
      final controller = await makeController();
      controller.themeMode = AppThemeMode.dark;
      final view = buildMacMenu(
        controller: controller,
        navigatorKey: GlobalKey<NavigatorState>(),
      )[3];

      expect(leafItem(view, 'Dark').label, '✓ Dark');
      expect(leafItem(view, 'Light').label, 'Light');
    });

    test('Toggle Settings Panel dispatches through the slot', () async {
      final controller = await makeController();
      var toggled = false;
      controller.onToggleSettingsPanel = () => toggled = true;
      final view = buildMacMenu(
        controller: controller,
        navigatorKey: GlobalKey<NavigatorState>(),
      )[3];

      leafItem(view, 'Toggle Settings Panel').onSelected?.call();
      expect(toggled, isTrue);
    });
  });

  group('Edit dispatch to the focused field', () {
    testWidgets('select all then cut moves the selection to the clipboard', (
      tester,
    ) async {
      final controller = await pumpFocusedField(tester);

      EditActions.selectAll();
      await tester.pump();
      EditActions.cut();
      await tester.pump();

      expect(controller.text, isEmpty);
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      expect(data?.text, 'one two three');
    });

    testWidgets('copy copies the selection without removing it', (
      tester,
    ) async {
      final controller = await pumpFocusedField(tester);
      controller.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 7,
      );

      EditActions.copy();
      await tester.pump();

      final data = await Clipboard.getData(Clipboard.kTextPlain);
      expect(data?.text, 'two');
      expect(controller.text, 'one two three');
    });

    testWidgets('paste inserts clipboard content at the caret', (tester) async {
      final controller = await pumpFocusedField(tester);
      await Clipboard.setData(const ClipboardData(text: ' PASTED'));

      EditActions.paste();
      await tester.pump();

      expect(controller.text, 'one two three PASTED');
    });

    testWidgets('undo and redo walk the editing history', (tester) async {
      final controller = await pumpFocusedField(tester);
      // Let the throttled undo stack commit before each edit.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.byType(TextField), 'changed text');
      await tester.pump(const Duration(milliseconds: 600));

      EditActions.undo();
      await tester.pump();
      expect(controller.text, 'one two three');

      EditActions.redo();
      await tester.pump();
      expect(controller.text, 'changed text');
    });
  });
}
