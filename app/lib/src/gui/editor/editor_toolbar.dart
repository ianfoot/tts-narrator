import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../controller/app_controller.dart';
import '../controller/l10n_labels.dart';
import '../platform/platform_detection.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icon_button.dart';

/// Extracted toolbar widget (JSON UI Schema `header_toolbar`) that receives
/// its injectable picker dependency directly so tests can fake the dialog.
/// Listens to [AppController] so controller-driven state (theme mode, dirty
/// indicator, completed track) stays live without the parent rebuilding.
class EditorToolbar extends StatefulWidget {
  const EditorToolbar({
    super.key,
    required this.controller,
    required this.railVisible,
    required this.onToggleRail,
    required this.pickDirectory,
    this.playingFull = false,
    required this.onTogglePlayFull,
    this.onShowGuard,
    this.onCleanupSegments,
  });

  final AppController controller;
  final bool railVisible;
  final VoidCallback onToggleRail;
  final Future<String?> Function()? pickDirectory;
  final bool playingFull;
  final VoidCallback onTogglePlayFull;
  final void Function(String message)? onShowGuard;

  /// Fired by the clean-up button; runs the shared confirm-and-delete flow.
  final VoidCallback? onCleanupSegments;

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  AppController get controller => widget.controller;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Opens the native directory picker for the output destination; leaves the
  /// current directory unchanged when cancelled or on a platform error.
  Future<void> _pickOutputDirectory() async {
    try {
      final path =
          await (widget.pickDirectory ??
              () => getDirectoryPath(initialDirectory: controller.outDir))();
      if (path == null) return;
      controller.outDir = path;
    } catch (_) {
      // The native picker can surface a platform error; keep the current
      // output directory rather than crashing the toolbar.
    }
  }

  Widget _buildAppearanceButton(AppTokens tokens) {
    final currentMode = controller.themeMode;
    return AppIconButton(
      key: const Key('appearanceToggleButton'),
      tooltip: _l10n.gui_editor_toolbar_appearanceTooltip(
        _themeModeLabel(currentMode),
      ),
      icon: Icon(switch (currentMode) {
        AppThemeMode.light => CupertinoIcons.sun_max,
        AppThemeMode.dark => CupertinoIcons.moon,
        AppThemeMode.system => CupertinoIcons.circle_lefthalf_fill,
      }),
      onPressed: () {
        controller.themeMode = switch (controller.themeMode) {
          AppThemeMode.system => AppThemeMode.light,
          AppThemeMode.light => AppThemeMode.dark,
          AppThemeMode.dark => AppThemeMode.system,
        };
      },
    );
  }

  String _themeModeLabel(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => _l10n.gui_editor_toolbar_themeModeAuto,
    AppThemeMode.light => _l10n.gui_editor_toolbar_themeModeLight,
    AppThemeMode.dark => _l10n.gui_editor_toolbar_themeModeDark,
  };

  Widget _buildOutputFolderButton() {
    return AppIconButton(
      key: const Key('outDirPickerButton'),
      tooltip:
          '${_l10n.gui_editor_toolbar_setOutputFolder} (${acceleratorLabel('E')})',
      icon: const Icon(CupertinoIcons.folder_badge_plus),
      onPressed: _pickOutputDirectory,
    );
  }

  /// Saves the document, mirroring the menu bar's File ▸ Save (⌘S). Disabled
  /// (greyed, via a null callback) while there is nothing unsaved.
  Widget _buildSaveButton() {
    return AppIconButton(
      key: const Key('editorSaveButton'),
      tooltip: '${_l10n.gui_editor_toolbar_save} (${acceleratorLabel('S')})',
      icon: const Icon(CupertinoIcons.square_arrow_down),
      onPressed: controller.dirty ? () => controller.save() : null,
    );
  }

  /// Clears the document; greyed out (null onPressed) when text is empty or
  /// narration is in progress.
  Widget _buildClearButton() {
    return AppIconButton(
      key: const Key('editorClearButton'),
      tooltip: 'Clear text (${acceleratorLabel('L', shift: true)})',
      icon: const Icon(CupertinoIcons.delete_left),
      onPressed: controller.canClearText ? () => controller.clearText() : null,
    );
  }

  Widget _buildDocumentTitle(AppTokens tokens) {
    final colors = tokens.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.dirty) ...[
          Container(
            key: const Key('dirtyDot'),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            controller.documentName.display(_l10n),
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.mono,
          ),
        ),
      ],
    );
  }

  /// Full-track play/stop toggle. Geometry, typography and colours all come
  /// from [AppButton], the same widget the narration screen's per-segment
  /// play/stop buttons use, so the two read identically.
  Widget? _buildFullPlayButton(AppTokens tokens) {
    if (controller.completedAudioPath == null) return null;

    final playing = widget.playingFull;
    final label = playing
        ? _l10n.gui_editor_toolbar_stop
        : _l10n.gui_editor_toolbar_playFull;
    return AppButton(
      key: const Key('editorFullPlayButton'),
      style: AppButtonStyle.outlined,
      compact: true,
      onPressed: widget.onTogglePlayFull,
      icon: Icon(
        playing ? CupertinoIcons.stop_circle : CupertinoIcons.play_fill,
        size: 14,
        color: tokens.colors.textPrimary,
      ),
      tooltip:
          '${_l10n.gui_editor_toolbar_playFull} (${acceleratorLabel('N')})',
      child: Text(label, style: tokens.typography.body),
    );
  }

  /// Deletes the last run's per-segment files, mirroring the menu bar's
  /// File ▸ Clean Up Segments… command. Only rendered while a finished run
  /// still has cleanable segments; the shared flow it dispatches to confirms
  /// deletion before touching anything.
  Widget _buildCleanupButton() {
    return AppIconButton(
      key: const Key('editorCleanupButton'),
      tooltip: _l10n.gui_editor_toolbar_cleanupSegments,
      icon: const Icon(CupertinoIcons.trash),
      onPressed: widget.onCleanupSegments,
    );
  }

  Widget _buildNarrateButton(AppTokens tokens) {
    return Tooltip(
      message: '${_l10n.gui_editor_toolbar_narrate} (${acceleratorLabel('N')})',
      child: AppButton(
        key: const Key('editorNarrateButton'),
        style: .filled,
        onPressed: () {
          final reason = controller.narrateBlockReason();
          if (reason != null) {
            widget.onShowGuard?.call(reason.message(_l10n));
            return;
          }
          controller.commands.onNarrate?.call();
        },
        compact: true,
        icon: const Icon(CupertinoIcons.play_fill, size: 18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(_l10n.gui_editor_toolbar_narrate)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = tokens.colors;
    final fullPlay = _buildFullPlayButton(tokens);
    return Container(
      height: AppMetrics.toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                key: const Key('railToggleButton'),
                tooltip: _l10n.gui_editor_toolbar_showHideSettings,
                icon: const Icon(CupertinoIcons.sidebar_left),
                onPressed: widget.onToggleRail,
              ),
              const SizedBox(width: 6),
              _buildAppearanceButton(tokens),
              const SizedBox(width: 6),
              AppIconButton(
                key: const Key('editorOpenButton'),
                tooltip:
                    '${_l10n.gui_editor_toolbar_openTextFile} (${acceleratorLabel('O')})',
                icon: const Icon(CupertinoIcons.folder),
                onPressed: () => controller.commands.onOpen?.call(),
              ),
              const SizedBox(width: 6),
              _buildOutputFolderButton(),
              const SizedBox(width: 6),
              _buildSaveButton(),
              const SizedBox(width: 6),
              _buildClearButton(),
            ],
          ),
          Expanded(child: Center(child: _buildDocumentTitle(tokens))),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildNarrateButton(tokens),
              if (fullPlay != null) ...[const SizedBox(width: 8), fullPlay],
              if (controller.canCleanupSegments) ...[
                const SizedBox(width: 8),
                _buildCleanupButton(),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
