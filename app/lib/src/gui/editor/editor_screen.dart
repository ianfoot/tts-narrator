import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controller/app_controller.dart';
import '../platform/platform_page.dart';

import '../platform/widgets/platform_text_field.dart';
import '../settings/settings_panel.dart';
import '../theme/app_tokens.dart';
import 'editor_status_bar.dart';
import 'editor_toolbar.dart';

/// Editor-first home screen (JSON UI Schema `header_toolbar` /
/// `editor_surface` / `status_bar`): a fixed toolbar with the document title,
/// a large serif editor, and a status bar with a live estimate pill.
///
/// All command dispatch goes through [AppController]; the screen only renders
/// controller state and surfaces controller guards (e.g. the empty-text
/// Narrate guard) as a transient animated banner.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.controller, this.pickDirectory});

  final AppController controller;

  /// Opens the native directory picker for the output destination; returns
  /// the chosen path or null when cancelled. Injectable so tests can fake
  /// the dialog without a platform selector. Defaults to [getDirectoryPath].
  final Future<String?> Function()? pickDirectory;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const _bannerDuration = Duration(milliseconds: 150);
  static const _railSlideDuration = Duration(milliseconds: 200);

  late final TextEditingController _textController;
  String? _guardMessage;
  Timer? _guardTimer;

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

  void _showGuard(String message) {
    _guardTimer?.cancel();
    setState(() => _guardMessage = message);
    _guardTimer = Timer(const Duration(milliseconds: 3500), () {
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
          EditorToolbar(
            controller: _controller,
            railVisible: _controller.settingsPanelVisible,
            onToggleRail: _controller.toggleSettingsPanel,
            pickDirectory: widget.pickDirectory,
            playingFull: _playingFull,
            onTogglePlayFull: _togglePlayFull,
            onShowGuard: _showGuard,
          ),
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
                  child: _controller.settingsPanelVisible
                      ? SettingsPanel(
                          key: const ValueKey('railVisible'),
                          controller: _controller,
                        )
                      : const SizedBox.shrink(key: ValueKey('railHidden')),
                ),
                Expanded(child: _buildEditor()),
              ],
            ),
          ),
          EditorStatusBar(controller: _controller),
        ],
      ),
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
            _isMac ? CupertinoIcons.exclamationmark_triangle : Icons.warning,
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
        key: const Key('configWarningsMessage'),
        style: _tokens.typography.body.copyWith(color: foreground),
      ),
    );
  }
}
