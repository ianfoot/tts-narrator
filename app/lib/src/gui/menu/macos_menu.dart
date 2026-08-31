import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/app_controller.dart';
import 'edit_actions.dart';

/// Builds the native macOS menu bar — the [PlatformMenu] tree the app mounts
/// through a [PlatformMenuBar] on macOS.
///
/// Pure configuration over the controller's platform-neutral command slots and
/// the app navigator: App (About/Preferences/Services/Hide/Quit), File
/// (Open/Narrate/Close), Edit (undo/redo/cut/copy/paste/select all, dispatched
/// to the focused text field by [EditActions]), View (Full Screen) and Window
/// (Minimize/Zoom/Front). The menu items are *not* widgets; they are sent to
/// the platform over the menu channel, so there is no [enabled] flag — the
/// Narrate item guards in its handler instead of graying out, and Linux/Windows
/// later bind the same controller slots to in-app menus.
List<PlatformMenu> buildMacMenu({
  required AppController controller,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  return <PlatformMenu>[
    _appMenu(controller),
    _fileMenu(controller, navigatorKey),
    _editMenu(),
    _viewMenu(),
    _windowMenu(),
  ];
}

PlatformMenu _appMenu(AppController controller) {
  return PlatformMenu(
    label: 'TTS Narrator',
    menus: <PlatformMenuItem>[
      const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
      PlatformMenuItemGroup(members: <PlatformMenuItem>[
        PlatformMenuItem(
          label: 'Preferences…',
          shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
          onSelected: () => controller.onPreferences?.call(),
        ),
      ]),
      const PlatformProvidedMenuItem(
        type: PlatformProvidedMenuItemType.servicesSubmenu,
      ),
      PlatformMenuItemGroup(members: <PlatformMenuItem>[
        const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.hideOtherApplications,
        ),
        const PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.showAllApplications,
        ),
        const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
      ]),
    ],
  );
}

PlatformMenu _fileMenu(
  AppController controller,
  GlobalKey<NavigatorState> navigatorKey,
) {
  return PlatformMenu(
    label: 'File',
    menus: <PlatformMenuItem>[
      PlatformMenuItem(
        label: 'Open Text…',
        shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
        onSelected: () => controller.onOpen?.call(),
      ),
      PlatformMenuItem(
        label: 'Narrate',
        shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
        onSelected: () {
          if (controller.narrateBlockReason() != null) return;
          controller.onNarrate?.call();
        },
      ),
      PlatformMenuItemGroup(members: <PlatformMenuItem>[
        PlatformMenuItem(
          label: 'Close',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
          onSelected: () => navigatorKey.currentState?.maybePop(),
        ),
      ]),
    ],
  );
}

PlatformMenu _editMenu() {
  return PlatformMenu(
    label: 'Edit',
    menus: <PlatformMenuItem>[
      PlatformMenuItem(
        label: 'Undo',
        shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
        onSelected: EditActions.undo,
      ),
      PlatformMenuItem(
        label: 'Redo',
        shortcut: const SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ),
        onSelected: EditActions.redo,
      ),
      PlatformMenuItemGroup(members: <PlatformMenuItem>[
        PlatformMenuItem(
          label: 'Cut',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
          onSelected: EditActions.cut,
        ),
        PlatformMenuItem(
          label: 'Copy',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
          onSelected: EditActions.copy,
        ),
        PlatformMenuItem(
          label: 'Paste',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          onSelected: EditActions.paste,
        ),
        PlatformMenuItem(
          label: 'Select All',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
          onSelected: EditActions.selectAll,
        ),
      ]),
    ],
  );
}

PlatformMenu _viewMenu() {
  return PlatformMenu(
    label: 'View',
    menus: const <PlatformMenuItem>[
      PlatformProvidedMenuItem(
        type: PlatformProvidedMenuItemType.toggleFullScreen,
      ),
    ],
  );
}

PlatformMenu _windowMenu() {
  return PlatformMenu(
    label: 'Window',
    menus: const <PlatformMenuItem>[
      PlatformProvidedMenuItem(
        type: PlatformProvidedMenuItemType.minimizeWindow,
      ),
      PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
      PlatformProvidedMenuItem(
        type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
      ),
    ],
  );
}
