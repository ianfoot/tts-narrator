import 'package:flutter/cupertino.dart';
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
              if (!controller.canCleanupSegments) return;
              _cleanUpSegments(controller, navigatorKey);
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

/// Runs the "Clean Up Segments…" flow: asks for confirmation (deleting the
/// per-segment files forfeits `--resume` reuse — a re-run would re-bill them),
/// then deletes the segments and reports how many were removed, or the error.
///
/// Dialogs mount on [navigatorKey]'s context since the menu bar itself has no
/// widget context.
Future<void> _cleanUpSegments(
  AppController controller,
  GlobalKey<NavigatorState> navigatorKey,
) async {
  final context = navigatorKey.currentState?.overlay?.context;
  if (context == null) return;
  // Capture the intended target: the dialog stays open while the menu bar
  // remains live, so a new run could change the output directory underneath.
  final targetDir = controller.lastRunOutputDir;

  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('Delete segment files?'),
      content: const Text(
        'This deletes the per-segment audio clips. The combined track and the '
        'manifest are kept. Deleted segments can\'t be reused by --resume, so '
        'a re-run narrates them again.',
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  // Re-validate before deleting: a new run may have started (and even
  // finished) while the dialog was open. If the target directory moved or
  // cleanup is no longer available, bail rather than deleting the new run's
  // segments.
  if (!controller.canCleanupSegments) return;
  if (controller.lastRunOutputDir != targetDir) return;

  try {
    final removed = await controller.cleanupSegments();
    if (!context.mounted) return;
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Segments deleted'),
        content: Text(
          'Removed $removed segment ${removed == 1 ? 'file' : 'files'}.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Cleanup failed'),
        content: Text('$e'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
