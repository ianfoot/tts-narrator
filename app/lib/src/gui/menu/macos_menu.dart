import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../cleanup_segments_flow.dart';
import '../controller/app_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart' show AppThemeMode;
import 'edit_actions.dart';

/// Builds the macOS menu bar — the [PlatformMenu] tree the app mounts through a
/// [PlatformMenuBar] on macOS. Linux/Windows get the in-app LinuxMenuBar
/// instead, which mirrors these commands as widgets.
///
/// Pure configuration over the controller's platform-neutral command slots and
/// the app navigator: App (About/Settings/Services/Hide/Quit), File
/// (Open/Save/Save As/Narrate), Edit (undo/redo/cut/copy/paste/select all,
/// dispatched to the focused text field by [EditActions]), View (Appearance,
/// Toggle Settings Panel, Full Screen) and Window (Minimize/Zoom/Front). The
/// menu items are *not* widgets; they are sent to the platform over the menu
/// channel, so there is no [enabled] flag — the Narrate item guards in its
/// handler instead of graying out.
///
/// [l10n] is threaded in rather than read from a context because the menu items
/// are plain values sent over the platform channel, not widgets — and the only
/// context available here is the navigator overlay's, which sits below the
/// `AppLocalizations` scope on some shells. The caller
/// ([PlatformMenuBarHost] in `platform/app_root.dart`) resolves it once from
/// its own context.
List<PlatformMenu> buildMacMenu({
  required AppController controller,
  required GlobalKey<NavigatorState> navigatorKey,
  required AppLocalizations l10n,
}) {
  return <PlatformMenu>[
    _appMenu(controller, l10n),
    _fileMenu(controller, navigatorKey, l10n),
    _editMenu(l10n),
    _viewMenu(controller, l10n),
    _windowMenu(l10n),
  ];
}

PlatformMenu _appMenu(AppController controller, AppLocalizations l10n) {
  return PlatformMenu(
    label: l10n.gui_menu_appMenu,
    menus: <PlatformMenuItem>[
      const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: l10n.gui_menu_settings,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: () => controller.commands.onSettings?.call(),
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
  AppLocalizations l10n,
) {
  return PlatformMenu(
    label: l10n.gui_menu_file,
    menus: <PlatformMenuItem>[
      PlatformMenuItem(
        label: l10n.gui_menu_openText,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
        onSelected: () => controller.commands.onOpen?.call(),
      ),
      PlatformMenuItem(
        label: l10n.gui_menu_outputFolder,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
        onSelected: () => controller.commands.onSetOutputFolder?.call(),
      ),
      PlatformMenuItem(
        label: l10n.gui_menu_narrate,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
        onSelected: () {
          if (controller.narrateBlockReason() != null) return;
          controller.commands.onNarrate?.call();
        },
      ),
      PlatformMenuItem(
        label: l10n.gui_menu_clear,
        shortcut: const SingleActivator(
          LogicalKeyboardKey.keyL,
          meta: true,
          shift: true,
        ),
        onSelected: () {
          // Guard: only clear when there's text and not narrating.
          if (!controller.canClearText) return;
          controller.clearText();
        },
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: l10n.gui_menu_save,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
            ),
            onSelected: () => controller.save(),
          ),
          PlatformMenuItem(
            label: l10n.gui_menu_saveAs,
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
            label: l10n.gui_menu_cleanUpSegments,
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
    ],
  );
}

PlatformMenu _editMenu(AppLocalizations l10n) {
  return PlatformMenu(
    label: l10n.gui_menu_edit,
    menus: <PlatformMenuItem>[
      PlatformMenuItem(
        label: l10n.gui_menu_undo,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
        onSelected: EditActions.undo,
      ),
      PlatformMenuItem(
        label: l10n.gui_menu_redo,
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
            label: l10n.gui_menu_cut,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyX,
              meta: true,
            ),
            onSelected: EditActions.cut,
          ),
          PlatformMenuItem(
            label: l10n.gui_menu_copy,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyC,
              meta: true,
            ),
            onSelected: EditActions.copy,
          ),
          PlatformMenuItem(
            label: l10n.gui_menu_paste,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyV,
              meta: true,
            ),
            onSelected: EditActions.paste,
          ),
          PlatformMenuItem(
            label: l10n.gui_menu_selectAll,
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

PlatformMenu _viewMenu(AppController controller, AppLocalizations l10n) {
  return PlatformMenu(
    label: l10n.gui_menu_view,
    menus: <PlatformMenuItem>[
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenu(
            label: l10n.gui_menu_appearance,
            menus: <PlatformMenuItem>[
              _appearanceItem(
                controller,
                AppThemeMode.system,
                l10n.gui_menu_themeModeAuto,
                l10n,
              ),
              _appearanceItem(
                controller,
                AppThemeMode.light,
                l10n.gui_menu_themeModeLight,
                l10n,
              ),
              _appearanceItem(
                controller,
                AppThemeMode.dark,
                l10n.gui_menu_themeModeDark,
                l10n,
              ),
            ],
          ),
          PlatformMenuItem(
            label: l10n.gui_menu_toggleRunSetupPanel,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.backslash,
              meta: true,
            ),
            onSelected: () =>
                controller.commands.onToggleRunSetupPanel?.call(),
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
  AppLocalizations l10n,
) {
  return PlatformMenuItem(
    label: controller.themeMode == mode
        ? '${l10n.gui_menu_checkmarkPrefix}$label'
        : label,
    onSelected: () => controller.themeMode = mode,
  );
}

PlatformMenu _windowMenu(AppLocalizations l10n) {
  return PlatformMenu(
    label: l10n.gui_menu_window,
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
