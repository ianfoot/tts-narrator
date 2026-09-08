import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controller/app_controller.dart';
import '../platform/widgets/platform_button.dart';
import '../platform/widgets/platform_icon_button.dart';
import '../theme/app_text_tokens.dart' show TextTokens, fillTextTemplate;
import '../theme/app_tokens.dart';

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
    this.onTogglePlayFull,
    this.onShowGuard,
    this.onCleanupSegments,
  });

  final AppController controller;
  final bool railVisible;
  final VoidCallback onToggleRail;
  final Future<String?> Function()? pickDirectory;
  final bool playingFull;
  final VoidCallback? onTogglePlayFull;
  final void Function(String message)? onShowGuard;

  /// Fired by the clean-up button; runs the shared confirm-and-delete flow.
  final VoidCallback? onCleanupSegments;

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  AppController get controller => widget.controller;

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

  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

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
    return PlatformIconButton(
      key: const Key('appearanceToggleButton'),
      tooltip: fillTextTemplate(
        TextTokens.gui_editor_toolbar_appearanceTooltip,
        {'mode': _themeModeLabel(currentMode)},
      ),
      icon: Icon(switch (currentMode) {
        AppThemeMode.light =>
          _isMac ? CupertinoIcons.sun_max : Icons.light_mode,
        AppThemeMode.dark => _isMac ? CupertinoIcons.moon : Icons.dark_mode,
        AppThemeMode.system =>
          _isMac ? CupertinoIcons.circle_lefthalf_fill : Icons.brightness_auto,
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
    AppThemeMode.system => TextTokens.gui_editor_toolbar_themeModeAuto,
    AppThemeMode.light => TextTokens.gui_editor_toolbar_themeModeLight,
    AppThemeMode.dark => TextTokens.gui_editor_toolbar_themeModeDark,
  };

  Widget _buildOutputFolderButton() {
    return PlatformIconButton(
      key: const Key('outDirPickerButton'),
      tooltip: TextTokens.gui_editor_toolbar_setOutputFolder,
      icon: Icon(_isMac ? CupertinoIcons.folder_badge_plus : Icons.output),
      onPressed: _pickOutputDirectory,
    );
  }

  /// Saves the document, mirroring the menu bar's File ▸ Save (⌘S). Disabled
  /// (greyed, via a null callback) while there is nothing unsaved.
  Widget _buildSaveButton() {
    return PlatformIconButton(
      key: const Key('editorSaveButton'),
      tooltip: TextTokens.gui_editor_toolbar_save,
      icon: Icon(
        _isMac ? CupertinoIcons.square_arrow_down : Icons.save_outlined,
      ),
      onPressed: controller.dirty ? () => controller.save() : null,
    );
  }

  /// Clears the document; greyed out (null onPressed) when text is empty or
  /// narration is in progress.
  Widget _buildClearButton() {
    return PlatformIconButton(
      key: const Key('editorClearButton'),
      tooltip: 'Clear text (⌘⇧L)',
      icon: Icon(_isMac ? CupertinoIcons.delete_left : Icons.clear),
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
            controller.documentName,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.mono.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget? _buildFullPlayButton(AppTokens tokens) {
    if (controller.completedAudioPath == null) return null;
    final colors = tokens.colors;
    final label = widget.playingFull
        ? TextTokens.gui_editor_toolbar_stop
        : TextTokens.gui_editor_toolbar_playFull;
    final btnIcon = Icon(
      _isMac
          ? (widget.playingFull
                ? CupertinoIcons.stop_circle
                : CupertinoIcons.play_fill)
          : (widget.playingFull
                ? Icons.stop_circle_outlined
                : Icons.play_arrow),
      size: 14,
      color: colors.textPrimary,
    );
    if (_isMac) {
      return CupertinoButton(
        key: const Key('editorFullPlayButton'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        onPressed: widget.onTogglePlayFull ?? () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: colors.borderSubtle, width: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DefaultTextStyle(
            style: tokens.typography.caption.copyWith(
              color: colors.textPrimary,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [btnIcon, const SizedBox(width: 4), Text(label)],
            ),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      key: const Key('editorFullPlayButton'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: widget.onTogglePlayFull ?? () {},
      icon: btnIcon,
      label: Text(
        label,
        style: tokens.typography.caption.copyWith(color: colors.textPrimary),
      ),
    );
  }

  /// Deletes the last run's per-segment files, mirroring the menu bar's
  /// File ▸ Clean Up Segments… command. Only rendered while a finished run
  /// still has cleanable segments; the shared flow it dispatches to confirms
  /// deletion before touching anything.
  Widget _buildCleanupButton() {
    return PlatformIconButton(
      key: const Key('editorCleanupButton'),
      tooltip: TextTokens.gui_editor_toolbar_cleanupSegments,
      icon: Icon(_isMac ? CupertinoIcons.trash : Icons.delete_outline),
      onPressed: widget.onCleanupSegments,
    );
  }

  Widget _buildNarrateButton(AppTokens tokens) {
    return Tooltip(
      message: TextTokens.gui_editor_toolbar_narrateShortcut,
      child: PlatformButton(
        key: const Key('editorNarrateButton'),
        onPressed: () {
          final reason = controller.narrateBlockReason();
          if (reason != null) {
            widget.onShowGuard?.call(reason);
            return;
          }
          controller.commands.onNarrate?.call();
        },
        compact: true,
        icon: Icon(
          _isMac ? CupertinoIcons.play_fill : Icons.play_arrow,
          size: 18,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [const Text(TextTokens.gui_editor_toolbar_narrate)],
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
              PlatformIconButton(
                key: const Key('railToggleButton'),
                tooltip: TextTokens.gui_editor_toolbar_showHideSettings,
                icon: Icon(
                  _isMac
                      ? CupertinoIcons.sidebar_left
                      : (widget.railVisible
                            ? Icons.settings
                            : Icons.settings_outlined),
                ),
                onPressed: widget.onToggleRail,
              ),
              const SizedBox(width: 6),
              _buildAppearanceButton(tokens),
              const SizedBox(width: 6),
              PlatformIconButton(
                key: const Key('editorOpenButton'),
                tooltip: TextTokens.gui_editor_toolbar_openTextFile,
                icon: Icon(_isMac ? CupertinoIcons.folder : Icons.folder_open),
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
