import 'package:flutter/material.dart';

import '../cleanup_segments_flow.dart';
import '../controller/app_controller.dart';
import '../platform/platform_detection.dart';
import '../../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart' show AppMetrics, AppThemeMode, AppTokens;
import 'edit_actions.dart';
import 'quit_app.dart';

/// The in-app menu bar for the platforms with no native one (Linux, Windows),
/// mounted as the home widget's root above the editor by `AppRoot`.
///
/// Renders the same commands as [buildMacMenu] — File, Edit and View — as real
/// widgets, so unlike [PlatformMenuItem] (which has no enabled flag) each item
/// can be *disabled* rather than silently swallowing taps: Narrate while
/// [AppController.narrateBlockReason] is non-null, Clear unless
/// [AppController.canClearText], Clean Up unless
/// [AppController.canCleanupSegments]. The macOS menu still guards inside its
/// handlers for the same reason.
///
/// Two deliberate differences from the macOS bar:
///
///  * **Shortcuts are labels, not bindings.** Items never pass
///    [MenuItemButton.shortcut], so building them needs no
///    `MaterialLocalizations` lookup and the bar works under the app's
///    `CupertinoApp` without a Material locale; the key is drawn as a
///    `trailingIcon` instead. The document-mutating and run-starting
///    accelerators live here rather than in the app's `CallbackShortcuts` map,
///    because Flutter keeps focus on the open menu's buttons, so the menu's own
///    key handling wins over an ancestor binding instead of both firing.
///  * **Quit is in File.** macOS gets the platform-provided Quit in its App
///    menu, which this bar has no equivalent for; the GTK/Qt convention puts
///    Quit at the end of File.
///
/// Rebuilds on [AppController] rather than a narrower notifier, because the
/// items gate on document and run state as well as theme; the controller
/// re-broadcasts all four inputs, so one listen keeps a newly-available command
/// from staying greyed out. The macOS bar needs no equivalent — the platform
/// rebuilds its items each time a menu opens.
class LinuxMenuBar extends StatelessWidget {
  const LinuxMenuBar({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
  });

  /// Supplies the command slots and the state that gates item availability.
  final AppController controller;

  /// Used by Clean Up Segments to reach the overlay that hosts its dialog.
  final GlobalKey<NavigatorState> navigatorKey;

  /// The app body, laid out below the bar.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = tokens.colors;
    return Material(
      // The bar paints its own background; this transparent Material exists
      // only so MenuBar and the buttons inherit a Material ancestor.
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.bgSurface,
                border: Border(bottom: BorderSide(color: colors.borderSubtle)),
              ),
              child: SizedBox(
                height: AppMetrics.toolbarHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MenuBar(
                    // MenuBar.style paints only the horizontal bar. Each
                    // dropdown is styled by its own SubmenuButton.menuStyle.
                    style: _barStyle,
                    children: [
                      SubmenuButton(
                        menuChildren: _fileItems(tokens, l10n),
                        menuStyle: _dropdownStyle(tokens),
                        style: _buttonStyle(tokens),
                        child: Text(l10n.gui_menu_file, style: _label(tokens)),
                      ),
                      SubmenuButton(
                        menuChildren: _editItems(tokens, l10n),
                        menuStyle: _dropdownStyle(tokens),
                        style: _buttonStyle(tokens),
                        child: Text(l10n.gui_menu_edit, style: _label(tokens)),
                      ),
                      SubmenuButton(
                        menuChildren: _viewItems(
                          tokens,
                          l10n,
                          controller.themeMode,
                        ),
                        menuStyle: _dropdownStyle(tokens),
                        style: _buttonStyle(tokens),
                        child: Text(l10n.gui_menu_view, style: _label(tokens)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  /// The bar itself: no fill of its own (the [DecoratedBox] behind it paints
  /// that) and no rounded corners, unlike Material's default menu bar.
  static final MenuStyle _barStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    side: const WidgetStatePropertyAll(BorderSide.none),
  );

  /// The submenu panels: raised surface, hairline border, app corner radius.
  MenuStyle _dropdownStyle(AppTokens tokens) => MenuStyle(
    backgroundColor: WidgetStatePropertyAll(tokens.colors.bgSurfaceElevated),
    elevation: const WidgetStatePropertyAll(4),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        side: BorderSide(color: tokens.colors.borderSubtle),
      ),
    ),
    side: WidgetStatePropertyAll(BorderSide(color: tokens.colors.borderSubtle)),
  );

  /// Shared shape and text for the bar's buttons. The foreground keeps the
  /// primary colour at reduced opacity when disabled, which is what makes an
  /// unavailable command read as unavailable.
  ButtonStyle _buttonStyle(AppTokens tokens) => ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? tokens.colors.textPrimary.withValues(alpha: 0.38)
          : tokens.colors.textPrimary,
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    textStyle: WidgetStatePropertyAll(_label(tokens)),
  );

  /// Every label in the bar: the 14pt control text in the primary colour,
  /// overriding whatever MenuBar/SubmenuButton would otherwise inherit.
  TextStyle _label(AppTokens tokens) =>
      tokens.typography.control.copyWith(color: tokens.colors.textPrimary);

  List<Widget> _fileItems(AppTokens tokens, AppLocalizations l10n) {
    final narrateBlocked = controller.narrateBlockReason() != null;
    final canClear = controller.canClearText;
    final canCleanUp = controller.canCleanupSegments;
    return [
      _item(
        tokens,
        l10n.gui_menu_openText,
        accelerator: 'O',
        onSelected: () => controller.commands.onOpen?.call(),
      ),
      _item(
        tokens,
        l10n.gui_menu_outputFolder,
        accelerator: 'E',
        onSelected: () => controller.commands.onSetOutputFolder?.call(),
      ),
      _item(
        tokens,
        l10n.gui_menu_narrate,
        accelerator: 'N',
        // Disabled rather than guarded: unlike a platform menu item, a widget menu can
        // show that the command is unavailable.
        onSelected: narrateBlocked
            ? null
            : () => controller.commands.onNarrate?.call(),
      ),
      _item(
        tokens,
        l10n.gui_menu_clear,
        accelerator: 'L',
        shift: true,
        onSelected: canClear ? controller.clearText : null,
      ),
      const _Separator(),
      _item(
        tokens,
        l10n.gui_menu_save,
        accelerator: 'S',
        onSelected: controller.save,
      ),
      _item(
        tokens,
        l10n.gui_menu_saveAs,
        accelerator: 'S',
        shift: true,
        onSelected: controller.saveAs,
      ),
      const _Separator(),
      _item(
        tokens,
        l10n.gui_menu_cleanUpSegments,
        onSelected: canCleanUp
            ? () {
                final overlayContext =
                    navigatorKey.currentState?.overlay?.context;
                if (overlayContext == null) return;
                runCleanupSegmentsFlow(
                  controller: controller,
                  context: overlayContext,
                );
              }
            : null,
      ),
      const _Separator(),
      // Settings is a document-neutral command, so it sits in its own group
      // between the document actions and the app-level one (Quit) rather than
      // being mixed in with Open/Save.
      _item(
        tokens,
        l10n.gui_menu_settings,
        accelerator: ',',
        onSelected: () => controller.commands.onSettings?.call(),
      ),
      const _Separator(),
      _item(tokens, l10n.gui_menu_quit, accelerator: 'Q', onSelected: quitApp),
    ];
  }

  List<Widget> _editItems(AppTokens tokens, AppLocalizations l10n) => [
    _item(
      tokens,
      l10n.gui_menu_undo,
      accelerator: 'Z',
      onSelected: EditActions.undo,
    ),
    _item(
      tokens,
      l10n.gui_menu_redo,
      accelerator: 'Z',
      shift: true,
      onSelected: EditActions.redo,
    ),
    const _Separator(),
    _item(
      tokens,
      l10n.gui_menu_cut,
      accelerator: 'X',
      onSelected: EditActions.cut,
    ),
    _item(
      tokens,
      l10n.gui_menu_copy,
      accelerator: 'C',
      onSelected: EditActions.copy,
    ),
    _item(
      tokens,
      l10n.gui_menu_paste,
      accelerator: 'V',
      onSelected: EditActions.paste,
    ),
    _item(
      tokens,
      l10n.gui_menu_selectAll,
      accelerator: 'A',
      onSelected: EditActions.selectAll,
    ),
  ];

  List<Widget> _viewItems(
    AppTokens tokens,
    AppLocalizations l10n,
    AppThemeMode themeMode,
  ) => [
    SubmenuButton(
      menuChildren: [
        _appearanceItem(
          tokens,
          themeMode,
          AppThemeMode.system,
          l10n.gui_menu_themeModeAuto,
          l10n,
        ),
        _appearanceItem(
          tokens,
          themeMode,
          AppThemeMode.light,
          l10n.gui_menu_themeModeLight,
          l10n,
        ),
        _appearanceItem(
          tokens,
          themeMode,
          AppThemeMode.dark,
          l10n.gui_menu_themeModeDark,
          l10n,
        ),
      ],
      menuStyle: _dropdownStyle(tokens),
      style: _buttonStyle(tokens),
      child: Text(l10n.gui_menu_appearance, style: _label(tokens)),
    ),
    _item(
      tokens,
      l10n.gui_menu_toggleRunSetupPanel,
      accelerator: '\\',
      onSelected: () => controller.commands.onToggleRunSetupPanel?.call(),
    ),
  ];

  /// A named appearance choice, with a leading checkmark when it is the active
  /// mode — the same label affordance the macOS bar uses, since
  /// [MenuItemButton] has no `checked` flag either.
  Widget _appearanceItem(
    AppTokens tokens,
    AppThemeMode current,
    AppThemeMode mode,
    String label,
    AppLocalizations l10n,
  ) {
    return MenuItemButton(
      onPressed: () => controller.themeMode = mode,
      child: Text(
        current == mode ? '${l10n.gui_menu_checkmarkPrefix}$label' : label,
        style: _label(tokens),
      ),
    );
  }

  /// One command row. [accelerator] is drawn as a trailing label rather than
  /// passed to [MenuItemButton.shortcut], which is what keeps the bar free of
  /// `MaterialLocalizations` lookups. A null [onSelected] disables the row.
  Widget _item(
    AppTokens tokens,
    String label, {
    String? accelerator,
    bool shift = false,
    required VoidCallback? onSelected,
  }) {
    return MenuItemButton(
      onPressed: onSelected,
      trailingIcon: accelerator == null
          ? null
          : Text(
              acceleratorLabel(accelerator, shift: shift),
              style: tokens.typography.control.copyWith(
                color: tokens.colors.textSecondary,
              ),
            ),
      child: Text(label, style: _label(tokens)),
    );
  }
}

/// A hairline divider between command groups, standing in for the platform
/// bars' separator groups.
class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppTokens.of(context).colors.borderSubtle,
      ),
    );
  }
}
