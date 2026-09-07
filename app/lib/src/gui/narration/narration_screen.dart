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
import '../platform/widgets/platform_progress_bar.dart';
import '../theme/app_tokens.dart';

/// Narration run view: a back-arrow header with the document name, a frozen
/// summary pill, a full-width progress rail, and 3-column segment cards
/// (status / body / play action) over a Cancel/Back action bar.
///
/// All run state lives in [AppController]; this screen merely subscribes. Back
/// cancels a still-active run through a confirmation dialog; otherwise it pops
/// straight back (the document already lives in the controller). A single
/// [AudioPlayer] plays one segment at a time (an auto-stop for the previous
/// clip) and reverts its button from Stop back to Play when a clip ends.
class NarrationScreen extends StatefulWidget {
  const NarrationScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<NarrationScreen> createState() => _NarrationScreenState();
}

class _NarrationScreenState extends State<NarrationScreen> {
  AudioPlayer? _player;
  int? _playingIndex;

  /// Guards against double-taps (or a concurrent system pop) stacking two
  /// confirm dialogs while one is already open.
  bool _confirming = false;

  /// How long to wait after the confirm dialog closes before popping the run
  /// view. The dialog route stays a "present" navigator route until its
  /// reverse transition finishes, so popping sooner would just re-pop it.
  static const _confirmLeaveDelay = Duration(milliseconds: 250);

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

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    // AudioPlayer only ever plays this screen's current clip; reaching the
    // end reverts the active button (⏹ -> ▶) automatically. Async load
    // failures also land on the state stream (rather than a thrown play()
    // error), so both revert paths clear the active index.
    player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingIndex = null);
    });
    player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        if (mounted && _playingIndex != null) {
          setState(() => _playingIndex = null);
        }
      }
    });
    _player = player;
    return player;
  }

  Future<void> _togglePlay(NarrationRunSegment segment) async {
    final path = segment.filePath;
    if (path == null || !File(path).existsSync()) return;
    if (_playingIndex == segment.index) {
      await _player?.stop();
      if (mounted) setState(() => _playingIndex = null);
      return;
    }
    await _player?.stop();
    final player = _ensurePlayer();
    try {
      await player.play(DeviceFileSource(path));
    } catch (_) {
      // A clip that fails to load (thrown synchronously) never enters the
      // playing state; the state-stream listener covers async failures.
      if (mounted) setState(() => _playingIndex = null);
      return;
    }
    if (mounted) setState(() => _playingIndex = segment.index);
  }

  /// Leaves the run view. While a run is generating every pop request (header
  /// Back, action-bar Back, ⌘W/Close, system back gesture) funnels through
  /// here via [PopScope]; the confirmation modal must play out before the
  /// route pops.
  Future<void> _onBack() async {
    final controller = _controller;
    final runActive = controller.narrating && !controller.runStopped;
    if (!runActive) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (_confirming) return;
    _confirming = true;
    bool confirmed;
    try {
      confirmed = await _confirmCancelActiveRun();
    } finally {
      _confirming = false;
    }
    if (!confirmed) return;
    controller.cancelRun();
    if (!mounted) return;
    // Wait out the dialog's reverse transition before popping: it stays a
    // present navigator route until the transition completes, and a pop while
    // it is would target the dialog instead of this view. The endOfFrame await
    // lets that closing frame tick past the dialog before we pop.
    await Future<void>.delayed(_confirmLeaveDelay);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  void _onCancel() => _controller.cancelRun();

  /// Confirms leaving a still-generating run. Returns true only when the user
  /// chose "Cancel Run" (stop generation + leave); "Back" keeps the run going.
  Future<bool> _confirmCancelActiveRun() async {
    const title = 'Cancel active narration run?';
    const message =
        'Generation stops now; completed clips stay playable in this session.';
    if (_isMac) {
      final result = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text(title),
          content: const Text(message),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancel Run'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Back'),
            ),
          ],
        ),
      );
      return result ?? false;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(title),
        content: const Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel Run'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  AppTokens get _tokens => AppTokens.of(context);

  IconData _playIcon() => _isMac ? CupertinoIcons.play_fill : Icons.play_arrow;
  IconData _stopIcon() =>
      _isMac ? CupertinoIcons.stop_circle : Icons.stop_circle_outlined;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final runActive = controller.narrating && !controller.runStopped;
    return PopScope(
      canPop: !runActive,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _onBack();
        }
      },
      child: PlatformPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(controller),
            if (controller.runConfig != null) _buildSummaryPill(controller),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildProgressBar(controller),
            ),
            if (controller.runPlanError != null)
              _buildMessageCard(controller.runPlanError!, isError: true)
            else if (controller.runError != null)
              _buildMessageCard(
                'Narration failed: ${controller.runError}',
                isError: true,
              )
            else if (controller.runStopped)
              _buildMessageCard('Narration was stopped.')
            else if (controller.runFinished)
              _buildMessageCard('Narration complete.'),
            Expanded(child: _buildSegmentList(controller)),
            _buildActionBar(controller),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppController controller) {
    final colors = _tokens.colors;
    return Container(
      height: AppMetrics.toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          PlatformIconButton(
            key: const Key('runBackButton'),
            tooltip: 'Back to editor',
            icon: Icon(_isMac ? CupertinoIcons.back : Icons.arrow_back),
            onPressed: () => _onBack(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Narrating: ${controller.documentName}',
              key: const Key('runHeaderTitle'),
              overflow: TextOverflow.ellipsis,
              style: _tokens.typography.headerSemibold.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Frozen run summary: model · voice | segments · minutes · cost (read from
  /// [AppController.runConfig], which is snapshotted at run start).
  Widget _buildSummaryPill(AppController controller) {
    final config = controller.runConfig!;
    final voice = config.voiceLabel ?? config.voice;
    final segments = controller.totalSegments;
    final minutes = controller.runEstimatedMinutes.round();
    final cost = formatCostUsd(controller.runEstimatedCostUsd);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _tokens.colors.bgSurfaceElevated,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${config.profile.alias} · $voice | $segments segments · '
          '~$minutes mins · ~$cost',
          key: const Key('runSummaryPill'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _tokens.typography.mono.copyWith(
            color: _tokens.colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageCard(String message, {bool isError = false}) {
    final colors = _tokens.colors;
    final bg = isError
        ? colors.accentError.withValues(alpha: 0.12)
        : colors.bgSurfaceElevated;
    final fg = isError ? colors.accentError : colors.textSecondary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(message, style: _tokens.typography.body.copyWith(color: fg)),
    );
  }

  Widget _buildSegmentList(AppController controller) {
    if (controller.runSegments.isEmpty) {
      return Center(
        child: Text(
          'No segments yet.',
          style: _tokens.typography.body.copyWith(
            color: _tokens.colors.textSecondary,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: controller.runSegments.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: AppMetrics.segmentGap),
        child: _buildSegmentCard(controller.runSegments[i]),
      ),
    );
  }

  /// 3-column segment card: status (32px) · body (flex) · action (100px).
  Widget _buildSegmentCard(NarrationRunSegment segment) {
    final colors = _tokens.colors;
    final trimmed = segment.paragraph.trim();
    return Container(
      padding: const EdgeInsets.all(AppMetrics.segmentCardPadding),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
        border: Border.all(color: colors.borderSubtle, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusColumn(segment),
          const SizedBox(width: 12),
          Expanded(child: _bodyColumn(segment, trimmed)),
          _actionColumn(segment),
        ],
      ),
    );
  }

  Widget _statusColumn(NarrationRunSegment segment) {
    final colors = _tokens.colors;
    final Widget indicator;
    if (segment.resumed) {
      indicator = Icon(
        _isMac ? CupertinoIcons.refresh : Icons.refresh,
        key: Key('segStatus_resumed_${segment.index}'),
        size: 18,
        color: colors.accentWarning,
      );
    } else if (segment.running) {
      indicator = SizedBox(
        key: Key('segStatus_processing_${segment.index}'),
        width: 18,
        height: 18,
        child: PlatformActivityIndicator(size: 18),
      );
    } else if (segment.filePath != null) {
      indicator = Container(
        key: Key('segStatus_completed_${segment.index}'),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: colors.accentSuccess,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isMac ? CupertinoIcons.check_mark : Icons.check,
          size: 12,
          color: colors.textOnAccent,
        ),
      );
    } else {
      indicator = Container(
        key: Key('segStatus_pending_${segment.index}'),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.textSecondary, width: 1.5),
        ),
      );
    }
    return SizedBox(width: 32, child: Center(child: indicator));
  }

  Widget _bodyColumn(NarrationRunSegment segment, String trimmed) {
    final colors = _tokens.colors;
    final body = _tokens.typography.body;
    final words = trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
    return Column(
      key: Key('segBody_${segment.index}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Segment ${segment.index + 1}',
              style: body.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            Text(
              ' · $words ${words == 1 ? 'word' : 'words'}',
              style: body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          trimmed,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: body.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  Widget _actionColumn(NarrationRunSegment segment) {
    final colors = _tokens.colors;
    final playable =
        segment.filePath != null && File(segment.filePath!).existsSync();
    final isPlaying = _playingIndex == segment.index;
    final Widget child;
    if (!playable) {
      child = Text(
        segment.running ? 'Processing...' : 'Pending',
        key: Key('segAction_${segment.index}'),
        textAlign: TextAlign.right,
        style: _tokens.typography.mono.copyWith(color: colors.textSecondary),
      );
    } else {
      child = _playStopButton(segment, isPlaying);
    }
    return SizedBox(
      width: AppMetrics.segmentActionWidth,
      child: Align(alignment: Alignment.centerRight, child: child),
    );
  }

  /// Compact `▶ Play` / `⏹ Stop` toggle sized to fit the 100px action column
  /// (the shared [PlatformButton] outlined geometry is too wide for it).
  Widget _playStopButton(NarrationRunSegment segment, bool isPlaying) {
    final colors = _tokens.colors;
    final label = isPlaying ? 'Stop' : 'Play';
    final icon = Icon(
      isPlaying ? _stopIcon() : _playIcon(),
      size: 14,
      color: colors.textPrimary,
    );
    final Widget button;
    if (_isMac) {
      button = CupertinoButton(
        key: Key('segAction_${segment.index}'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        onPressed: () => _togglePlay(segment),
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
        key: Key('segAction_${segment.index}'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => _togglePlay(segment),
        icon: icon,
        label: Text(
          label,
          style: _tokens.typography.caption.copyWith(color: colors.textPrimary),
        ),
      );
    }
    // Reused clips get a Material-only tooltip (Cupertino has none).
    if (segment.resumed && !_isMac) {
      return Tooltip(message: 'Resumed — tap to play', child: button);
    }
    return button;
  }

  Widget _buildProgressBar(AppController controller) {
    final colors = _tokens.colors;
    return PlatformProgressBar(
      key: const Key('runProgressBar'),
      value: controller.runProgress,
      valueColor: colors.accentPrimary,
      backgroundColor: colors.borderSubtle,
      minHeight: 6,
    );
  }

  Widget _buildActionBar(AppController controller) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          PlatformButton(
            key: const Key('runActionBack'),
            onPressed: () => _onBack(),
            style: PlatformButtonStyle.outlined,
            child: const Text('Back'),
          ),
          const Spacer(),
          if (controller.narrating && !controller.runStopped)
            PlatformButton(
              key: const Key('runCancelButton'),
              onPressed: _onCancel,
              icon: Icon(_isMac ? CupertinoIcons.stop : Icons.stop),
              child: const Text('Cancel Run'),
            ),
        ],
      ),
    );
  }
}
