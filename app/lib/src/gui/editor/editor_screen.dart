import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../platform/platform_page.dart';
import '../platform/widgets/platform_button.dart';
import '../platform/widgets/platform_icon_button.dart';
import '../platform/widgets/platform_text_field.dart';
import '../settings/inspector_rail.dart';
import '../theme/app_tokens.dart';

/// Editor-first home screen (JSON UI Schema `header_toolbar` /
/// `editor_surface` / `status_bar`): a fixed toolbar with the document title,
/// a large serif editor, and a status bar with a live estimate pill.
///
/// All command dispatch goes through [AppController]; the screen only renders
/// controller state and surfaces controller guards (e.g. the empty-text
/// Narrate guard) as a transient animated banner.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const _guardDuration = Duration(milliseconds: 3500);
  static const _bannerDuration = Duration(milliseconds: 150);
  static const _tickerDuration = Duration(milliseconds: 100);
  static const _railSlideDuration = Duration(milliseconds: 200);

  late final TextEditingController _textController;
  String? _guardMessage;
  Timer? _guardTimer;
  bool _railVisible = true;

  /// Plays the completed combined track from a successful narration run. The
  /// button lives on the status bar and persists after leaving the run view,
  /// so the finished file stays one tap away until the next run replaces it.
  AudioPlayer? _player;
  bool _playingFull = false;

  AppController get _controller => widget.controller;

  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: _controller.text);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _textController.dispose();
    _guardTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // A new run clears the completed track path; stop any playback of the
    // prior track so stale audio doesn't keep playing under the run view.
    if (_playingFull && _controller.completedAudioPath == null) {
      _player?.stop();
      _playingFull = false;
    }
    setState(() {
      if (_textController.text != _controller.text) {
        _textController.text = _controller.text;
      }
    });
  }

  void _onTextChanged(String value) => _controller.setText(value);

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    // One player for the full track only (per-segment clips play on the run
    // view). Reaching the end — or an explicit stop — reverts the button from
    // Stop back to Play automatically.
    player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingFull = false);
    });
    player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        if (mounted && _playingFull) {
          setState(() => _playingFull = false);
        }
      }
    });
    _player = player;
    return player;
  }

  Future<void> _togglePlayFull() async {
    if (_playingFull) {
      await _player?.stop();
      if (mounted) setState(() => _playingFull = false);
      return;
    }
    final path = _controller.completedAudioPath;
    if (path == null || !File(path).existsSync()) return;
    await _player?.stop();
    final player = _ensurePlayer();
    try {
      await player.play(DeviceFileSource(path));
    } catch (_) {
      // A file that fails to load synchronously never enters the playing
      // state; the state-stream listener covers async failures.
      if (mounted) setState(() => _playingFull = false);
      return;
    }
    if (mounted) setState(() => _playingFull = true);
  }

  /// Compact `▶ Play Full` / `⏹ Stop` toggle for the completed combined track,
  /// shown only while a finished run's audio file is on disk.
  Widget _buildFullPlayButton() {
    final colors = _tokens.colors;
    final label = _playingFull ? 'Stop' : 'Play Full';
    final icon = Icon(
      _isMac
          ? (_playingFull ? CupertinoIcons.stop_circle : CupertinoIcons.play_fill)
          : (_playingFull ? Icons.stop_circle_outlined : Icons.play_arrow),
      size: 14,
      color: colors.textPrimary,
    );
    final Widget button;
    if (_isMac) {
      button = CupertinoButton(
        key: const Key('editorFullPlayButton'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        onPressed: _togglePlayFull,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: colors.borderSubtle, width: 0.8),
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          ),
          child: DefaultTextStyle(
            style: _tokens.typography.caption.copyWith(
              color: colors.textPrimary,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [icon, const SizedBox(width: 4), Text(label)],
            ),
          ),
        ),
      );
    } else {
      button = OutlinedButton.icon(
        key: const Key('editorFullPlayButton'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: _togglePlayFull,
        icon: icon,
        label: Text(
          label,
          style: _tokens.typography.caption.copyWith(color: colors.textPrimary),
        ),
      );
    }
    return button;
  }

  void _onOpenPressed() => _controller.onOpen?.call();

  void _onNarratePressed() {
    final reason = _controller.narrateBlockReason();
    if (reason != null) {
      _showGuard(reason);
      return;
    }
    // Dispatch through the Narrate slot (AppRoot navigates to the run view).
    _controller.onNarrate?.call();
  }

  void _toggleRail() => setState(() => _railVisible = !_railVisible);

  void _showGuard(String message) {
    _guardTimer?.cancel();
    setState(() => _guardMessage = message);
    _guardTimer = Timer(_guardDuration, () {
      if (mounted) setState(() => _guardMessage = null);
    });
  }

  AppTokens get _tokens => AppTokens.of(context);

  @override
  Widget build(BuildContext context) {
    return PlatformPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          if (_controller.configWarnings.isNotEmpty)
            _buildConfigWarningsBanner(_controller.configWarnings),
          AnimatedSwitcher(
            duration: _bannerDuration,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _guardMessage == null
                ? const SizedBox.shrink(key: Key('guardSlot'))
                : _buildGuardBanner(
                    _guardMessage!,
                    key: const Key('narrateGuard'),
                  ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: _railSlideDuration,
                  reverseDuration: _railSlideDuration,
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(-1, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                  child: _railVisible
                      ? InspectorRail(
                          key: const ValueKey('railVisible'),
                          controller: _controller,
                        )
                      : const SizedBox.shrink(key: ValueKey('railHidden')),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildEditor()),
                      _buildStatusBar(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Toolbar (JSON UI Schema `header_toolbar`) --------------------------

  Widget _buildToolbar() {
    final colors = _tokens.colors;
    final shortcutStyle = _tokens.typography.caption.copyWith(
      color: colors.textSecondary,
    );
    final leftZone = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlatformIconButton(
          key: const Key('railToggleButton'),
          tooltip: 'Show / hide settings',
          icon: Icon(
            _isMac
                ? CupertinoIcons.sidebar_left
                : (_railVisible ? Icons.settings : Icons.settings_outlined),
          ),
          onPressed: _toggleRail,
        ),
        const SizedBox(width: 8),
        PlatformIconButton(
          key: const Key('editorOpenButton'),
          tooltip: 'Open text file (⌘O)',
          icon: Icon(_isMac ? CupertinoIcons.folder : Icons.folder_open),
          onPressed: _onOpenPressed,
        ),
        const SizedBox(width: 4),
        Text('⌘O', style: shortcutStyle),
        if (_controller.completedAudioPath != null) ...[
          const SizedBox(width: 8),
          _buildFullPlayButton(),
        ],
      ],
    );
    final rightZone = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlatformButton(
          key: const Key('editorNarrateButton'),
          onPressed: _onNarratePressed,
          icon: Icon(
            _isMac ? CupertinoIcons.play_fill : Icons.play_arrow,
            size: 18,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Narrate'),
              const SizedBox(width: 4),
              Text(
                '⌘N',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: leftZone),
          ),
          Expanded(child: Center(child: _buildDocumentTitle())),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: rightZone),
          ),
        ],
      ),
    );
  }

  /// Document filename plus the 6px `•` modified indicator when unsaved
  /// changes exist (JSON UI Schema `modifiedIndicator`).
  Widget _buildDocumentTitle() {
    final colors = _tokens.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_controller.dirty) ...[
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
            _controller.documentName,
            overflow: TextOverflow.ellipsis,
            style: _tokens.typography.mono.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }

  // --- Writing canvas (JSON UI Schema `editor_surface`) -------------------

  Widget _buildEditor() {
    final colors = _tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppMetrics.editorOuterPadding,
        24,
        AppMetrics.editorOuterPadding,
        24,
      ),
      child: PlatformTextField(
        key: const Key('editorTextField'),
        controller: _textController,
        onChanged: _onTextChanged,
        hintText: 'Type, paste text, or open a .txt file...',
        hintStyle: _tokens.typography.editorBody.copyWith(
          color: colors.textSecondary.withValues(alpha: 0.4),
        ),
        maxLines: null,
        expands: true,
        autofocus: true,
        style: _tokens.typography.editorBody.copyWith(
          color: colors.textPrimary,
        ),
      ),
    );
  }

  // --- Status bar (JSON UI Schema `status_bar`) ---------------------------

  Widget _buildStatusBar() {
    final colors = _tokens.colors;
    final words = _formatCount(_controller.wordCount);
    final chars = _formatCount(_controller.charCount);
    final segments = _controller.plannedSegments.length;
    final minutes = _controller.estimatedMinutes.round();
    final cost = formatCostUsd(_controller.estimatedCostUsd);
    return Container(
      height: AppMetrics.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: AnimatedSwitcher(
              duration: _tickerDuration,
              child: Text(
                '$words words · $chars characters',
                key: ValueKey('$words-$chars'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: _tokens.typography.mono.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedSwitcher(
                duration: _tickerDuration,
                child: Container(
                  key: ValueKey('$segments-$minutes-$cost'),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.bgSurfaceElevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$segments segments · ~$minutes mins · ~$cost est.',
                    key: const Key('editorEstimate'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: _tokens.typography.mono.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Thousands separators, e.g. 1240 -> "1,240".
  String _formatCount(int value) {
    final s = value.toString();
    if (s.length <= 3) return s;
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  // --- Transient warning banner ------------------------------------------

  Widget _buildGuardBanner(String message, {Key? key}) {
    final colors = _tokens.colors;
    final background = colors.accentWarning.withValues(alpha: 0.15);
    final foreground = colors.accentWarning;
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: background,
      child: Row(
        children: [
          Icon(
            _isMac
                ? CupertinoIcons.exclamationmark_triangle
                : Icons.warning,
            size: 14,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Text(
            'Cannot narrate: $message',
            key: const Key('narrateGuardMessage'),
            style: _tokens.typography.body.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }

  //  Persistent, non-fatal notice that one or more model config files were--
  Widget _buildConfigWarningsBanner(List<String> warnings) {
    final colors = _tokens.colors;
    final background = colors.accentWarning.withValues(alpha: 0.12);
    final foreground = colors.accentWarning;
    return Container(
      key: const Key('configWarnings'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: background,
      child: Text(
        warnings.join('\n'),
        key:  const Key('configWarningsMessage'),
        style: _tokens.typography.body.copyWith(color: foreground),
      ),
    );
  }
}