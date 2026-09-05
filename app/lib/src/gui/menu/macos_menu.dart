import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../cleanup_segments_flow.dart';
import '../controller/app_controller.dart';
import '../theme/app_tokens.dart' show AppThemeMode;
import 'edit_actions.dart';

/// Builds the macOS menu bar — the [PlatformMenu] tree the app mounts through a
/// [PlatformMenuBar] on macOS (kept macOS-only for now; Linux/Windows bind the
/// same controller slots to in-app menus later).
///
/// Pure configuration over the controller's platform-neutral command slots and
/// the app navigator: App (About/Preferences/Services/Hide/Quit), File
/// (Open/Save/Save As/Narrate/Close), Edit (undo/redo/cut/copy/paste/select
/// all, dispatched to the focused text field by [EditActions]), View
/// (Appearance, Toggle Settings Panel, Full Screen) and Window
/// (Minimize/Zoom/Front). The menu items are *not* widgets; they are sent to
/// the platform over the menu channel, so there is no [enabled] flag — the
/// Narrate item guards in its handler instead of graying out.
List<PlatformMenu> buildMacMenu({
  required AppController controller,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  return <PlatformMenu>[
    _appMenu(controller),
    _fileMenu(controller, navigatorKey),
    _editMenu(),
    _viewMenu(controller),
    _windowMenu(),
  ];
}

PlatformMenu _appMenu(AppController controller) {
  return PlatformMenu(
    label: 'TTS Narrator',
    menus: <PlatformMenuItem>[
      const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Preferences…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: () => controller.onPreferences?.call(),
          ),
        ],
      ),
      const PlatformProvidedMenuItem(
        type: PlatformProvidedMenuItemType.servicesSubmenu,
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hide,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hideOtherApplications,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.showAllApplications,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.quit,
          ),
        ],
      ),
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
        label: 'Output Folder…',
        shortcut: const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
        onSelected: () => controller.onSetOutputFolder?.call(),
      ),
      PlatformMenuItem(
        label: 'Narrate',
        shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
        onSelected: () {
          if (controller.narrateBlockReason() != null) return;
          controller.onNarrate?.call();
        },
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Save',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
            ),
            onSelected: () => controller.save(),
          ),
          PlatformMenuItem(
            label: 'Save As…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
              shift: true,
            ),
            onSelected: () => controller.saveAs(),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Clean Up Segments…',
            onSelected: () {
              // Menu items have no [enabled] flag; guard here so the command
              // is a no-op before any run leaves cleanable segments behind.
              // The shared flow then confirms before deleting anything.
              if (!controller.canCleanupSegments) return;
              final context = navigatorKey.currentState?.overlay?.context;
              if (context == null) return;
              runCleanupSegmentsFlow(controller: controller, context: context);
            },
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Close',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyW,
              meta: true,
            ),
            onSelected: () => navigatorKey.currentState?.maybePop(),
          ),
        ],
      ),
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
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Cut',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyX,
              meta: true,
            ),
            onSelected: EditActions.cut,
          ),
          PlatformMenuItem(
            label: 'Copy',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyC,
              meta: true,
            ),
            onSelected: EditActions.copy,
          ),
          PlatformMenuItem(
            label: 'Paste',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyV,
              meta: true,
            ),
            onSelected: EditActions.paste,
          ),
          PlatformMenuItem(
            label: 'Select All',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyA,
              meta: true,
            ),
            onSelected: EditActions.selectAll,
          ),
        ],
      ),
    ],
  );
}

PlatformMenu _viewMenu(AppController controller) {
  return PlatformMenu(
    label: 'View',
    menus: <PlatformMenuItem>[
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenu(
            label: 'Appearance',
            menus: <PlatformMenuItem>[
              _appearanceItem(controller, AppThemeMode.system, 'Auto'),
              _appearanceItem(controller, AppThemeMode.light, 'Light'),
              _appearanceItem(controller, AppThemeMode.dark, 'Dark'),
            ],
          ),
          PlatformMenuItem(
            label: 'Toggle Settings Panel',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.backslash,
              meta: true,
            ),
            onSelected: () => controller.onToggleSettingsPanel?.call(),
          ),
        ],
      ),
      const PlatformProvidedMenuItem(
        type: PlatformProvidedMenuItemType.toggleFullScreen,
      ),
    ],
  );
}

/// A named appearance choice, with a leading checkmark when it is the active
/// mode. The checkmark is a label affordance (platform menu items carry no
/// checked flag); the menu rebuilds because AppRoot listens to the controller.
PlatformMenuItem _appearanceItem(
  AppController controller,
  AppThemeMode mode,
  String label,
) {
  return PlatformMenuItem(
    label: controller.themeMode == mode ? '✓ $label' : label,
    onSelected: () => controller.themeMode = mode,
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
