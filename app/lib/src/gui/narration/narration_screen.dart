import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../platform/platform_page.dart';
import '../platform/widgets/platform_activity_indicator.dart';
import '../platform/widgets/platform_button.dart';
import '../platform/widgets/platform_icon_button.dart';
import '../platform/widgets/platform_list_tile.dart';
import '../platform/widgets/platform_progress_bar.dart';

/// Narration run view: a banner (model/voice + estimate), a per-chunk list
/// (pending / running / done / resumed) with in-app playback, a determinate
/// progress bar, and Cancel + Back.
///
/// All run state lives in [AppController]; this screen merely subscribes. Back
/// preserves the document (it already lives in the controller); while a run is
/// active Back cancels first.
class NarrationScreen extends StatefulWidget {
  const NarrationScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<NarrationScreen> createState() => _NarrationScreenState();
}

class _NarrationScreenState extends State<NarrationScreen> {
  AudioPlayer? _player;
  int? _playingIndex;

  AppController get _controller => widget.controller;

  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _player?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlay(NarrationRunChunk chunk) async {
    final path = chunk.filePath;
    if (path == null || !File(path).existsSync()) return;
    if (_playingIndex == chunk.index) {
      await _player?.stop();
      if (mounted) setState(() => _playingIndex = null);
      return;
    }
    await _player?.stop();
    final player = _player ??= AudioPlayer();
    await player.play(DeviceFileSource(path));
    if (mounted) setState(() => _playingIndex = chunk.index);
  }

  void _onBack() {
    if (_controller.narrating) _controller.cancelRun();
    Navigator.of(context).pop();
  }

  void _onCancel() => _controller.cancelRun();

  Color _accentColor() => _isMac
      ? CupertinoTheme.brightnessOf(context) == Brightness.dark
          ? CupertinoColors.activeBlue
          : CupertinoColors.systemBlue
      : Theme.of(context).colorScheme.primary;

  Color _textColor() => _isMac
      ? CupertinoTheme.brightnessOf(context) == Brightness.dark
          ? CupertinoColors.white
          : CupertinoColors.black
      : Theme.of(context).colorScheme.onSurface;

  Color _mutedColor() => _isMac
      ? CupertinoColors.systemGrey
      : Theme.of(context).colorScheme.onSurfaceVariant;

  IconData _playIcon() => _isMac ? CupertinoIcons.play_fill : Icons.play_arrow;
  IconData _stopIcon() =>
      _isMac ? CupertinoIcons.stop_circle : Icons.stop_circle_outlined;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PlatformPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(controller),
          if (controller.runConfig != null) _buildBanner(controller),
          if (controller.runPlanError != null)
            _buildMessageCard(controller.runPlanError!, isError: true)
          else if (controller.runError != null)
            _buildMessageCard('Narration failed: ${controller.runError}',
                isError: true)
          else if (controller.runStopped)
            _buildMessageCard('Narration was stopped.'),
          if (controller.runFinished)
            _buildMessageCard('Narration complete.'),
          Expanded(child: _buildChunkList(controller)),
          _buildProgressBar(controller),
          _buildActionBar(controller),
        ],
      ),
    );
  }

  Widget _buildHeader(AppController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        'Narrate — ${controller.documentName}',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: _accentColor(),
        ),
      ),
    );
  }

  Widget _buildBanner(AppController controller) {
    final config = controller.runConfig!;
    final profile = config.profile;
    final minutes = controller.runEstimatedMinutes;
    final cost = formatCostUsd(controller.runEstimatedCostUsd);
    final voice = config.voiceLabel ?? config.voice;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: _isMac
                ? CupertinoColors.separator
                : Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${profile.alias} — $voice',
            key: const Key('runBannerModelVoice'),
            style: TextStyle(fontSize: 13, color: _textColor()),
          ),
          const SizedBox(height: 2),
          Text(
            '${controller.totalChunks} chunks · ${minutes.toStringAsFixed(1)} min · $cost',
            key: const Key('runBannerEstimate'),
            style: TextStyle(fontSize: 12, color: _mutedColor()),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(String message, {bool isError = false}) {
    final bg = isError
        ? (_isMac
              ? CupertinoColors.systemRed.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.errorContainer)
        : (_isMac
              ? CupertinoColors.systemGrey.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surfaceContainerHighest);
    final fg = isError
        ? (_isMac
              ? CupertinoColors.systemRed
              : Theme.of(context).colorScheme.onErrorContainer)
        : _mutedColor();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(message, style: TextStyle(fontSize: 13, color: fg)),
    );
  }

  Widget _buildChunkList(AppController controller) {
    if (controller.runChunks.isEmpty) {
      return Center(
        child: Text('No chunks yet.', style: TextStyle(color: _mutedColor())),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: controller.runChunks.length,
      itemBuilder: (context, i) => _buildChunkTile(controller.runChunks[i]),
    );
  }

  Widget _buildChunkTile(NarrationRunChunk chunk) {
    final words = chunk.paragraph.split(RegExp(r'\s+')).length;
    final preview = chunk.paragraph.length > 90
        ? '${chunk.paragraph.substring(0, 90)}…'
        : chunk.paragraph;
    final playable = chunk.filePath != null && File(chunk.filePath!).existsSync();
    final isPlaying = _playingIndex == chunk.index;
    final leading = chunk.resumed
        ? Icon(_isMac ? CupertinoIcons.refresh : Icons.replay_circle_filled,
            color: isPlaying ? _accentColor() : _mutedColor())
        : chunk.running
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: PlatformActivityIndicator(size: 16),
              )
            : Icon(
                _isMac ? CupertinoIcons.circle : Icons.radio_button_unchecked,
                size: 16,
                color: _mutedColor(),
              );
    final trailing = (chunk.resumed || playable)
        ? PlatformIconButton(
            tooltip: chunk.resumed ? 'Resumed — tap to play' : 'Play',
            icon: Icon(isPlaying ? _stopIcon() : _playIcon()),
            onPressed: () => _togglePlay(chunk),
          )
        : null;
    return PlatformListTile(
      leading: leading,
      title: Text('[${chunk.index + 1}/${totalChunks()}] $preview'),
      subtitle: Text(words == 1 ? '$words word' : '$words words'),
      trailing: trailing,
    );
  }

  int totalChunks() => _controller.totalChunks;

  Widget _buildProgressBar(AppController controller) {
    final accent = _accentColor();
    final track = _isMac
        ? CupertinoColors.systemGrey.withValues(alpha: 0.25)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: PlatformProgressBar(
        key: const Key('runProgressBar'),
        value: controller.runProgress,
        valueColor: accent,
        backgroundColor: track,
      ),
    );
  }

  Widget _buildActionBar(AppController controller) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          PlatformButton(
            key: const Key('runBackButton'),
            onPressed: _onBack,
            style: PlatformButtonStyle.outlined,
            child: const Text('Back'),
          ),
          const Spacer(),
          if (controller.narrating && !controller.runStopped)
            PlatformButton(
              key: const Key('runCancelButton'),
              onPressed: _onCancel,
              icon: Icon(_isMac ? CupertinoIcons.stop : Icons.stop),
              child: const Text('Cancel'),
            ),
        ],
      ),
    );
  }
}