import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';

import '../../../l10n/app_localizations.dart';
import '../controller/app_controller.dart';
import '../controller/l10n_labels.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/progress_bar.dart';
import 'active_run_confirm.dart';

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

  Future<void> _togglePlay(NarrationSegment segment) async {
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
  /// Back, action-bar Back, system back gesture) funnels through here via
  /// [PopScope]; the confirmation modal must play out before the route pops.
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
      confirmed = await _confirmCancel();
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

  /// Confirms leaving via the extracted dialog class.
  Future<bool> _confirmCancel() =>
      ActiveRunConfirmDialog.show(context: context);

  AppTokens get _tokens => AppTokens.of(context);

  AppLocalizations get _l10n => AppLocalizations.of(context);

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
      child: CupertinoPageScaffold(
        backgroundColor: AppTokens.of(context).colors.bgApp,
        child: SafeArea(
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
                  _l10n.gui_narration_narrationFailed(controller.runError!),
                  isError: true,
                )
              else if (controller.runStopped)
                _buildMessageCard(_l10n.gui_narration_narrationStopped)
              else if (controller.runFinished)
                _buildMessageCard(_l10n.gui_narration_narrationComplete),
              Expanded(child: _buildSegmentList(controller)),
              _buildActionBar(controller),
            ],
          ),
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
          AppIconButton(
            key: const Key('runBackButton'),
            tooltip: _l10n.gui_narration_backToEditor,
            icon: const Icon(CupertinoIcons.back),
            onPressed: () => _onBack(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _l10n.gui_narration_narratingTitle(
                controller.documentName.display(_l10n),
              ),
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
    final cost = controller.runEstimatedCostUsd.costLabel(_l10n);
    final segmentLabel = _l10n.core_plurals_segment(segments);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _tokens.colors.bgSurfaceElevated,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _l10n.gui_narration_summaryPill(
            config.profile.alias,
            voice,
            segments,
            segmentLabel,
            minutes.toString(),
            cost,
          ),
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
          _l10n.gui_narration_noSegmentsYet,
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

  /// 3-column segment card: status (32px) · body (flex) · action.
  Widget _buildSegmentCard(NarrationSegment segment) {
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
          SizedBox(width: AppMetrics.segmentActionWidth),
          _actionColumn(segment),
        ],
      ),
    );
  }

  Widget _statusColumn(NarrationSegment segment) {
    final colors = _tokens.colors;
    final Widget indicator;
    if (segment.resumed) {
      indicator = Icon(
        CupertinoIcons.refresh,
        key: Key('segStatus_resumed_${segment.index}'),
        size: 18,
        color: colors.accentWarning,
      );
    } else if (segment.running) {
      indicator = SizedBox(
        key: Key('segStatus_processing_${segment.index}'),
        width: 18,
        height: 18,
        child: const CupertinoActivityIndicator(radius: 9),
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
          CupertinoIcons.check_mark,
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

  Widget _bodyColumn(NarrationSegment segment, String trimmed) {
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
              _l10n.gui_narration_segmentLabel(segment.index + 1),
              style: body.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            Text(
              _l10n.gui_narration_wordCountSuffix(
                words,
                _l10n.core_plurals_word(words),
              ),
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

  Widget _actionColumn(NarrationSegment segment) {
    final colors = _tokens.colors;
    final playable =
        segment.filePath != null && File(segment.filePath!).existsSync();
    final isPlaying = _playingIndex == segment.index;
    final Widget child;
    if (!playable) {
      child = Text(
        segment.running
            ? _l10n.gui_narration_processing
            : _l10n.gui_narration_pending,
        key: Key('segAction_${segment.index}'),
        textAlign: TextAlign.right,
        style: _tokens.typography.mono.copyWith(color: colors.textSecondary),
      );
    } else {
      child = _playStopButton(segment, isPlaying);
    }
    // Sized to its content rather than a fixed width: the button's width
    // follows its label, so a hard column width would clip it on narrow
    // surfaces.
    return Align(alignment: Alignment.centerRight, child: child);
  }

  /// Compact `▶ Play` / `⏹ Stop` toggle, built from the same [AppButton] as
  /// the editor toolbar's full-track button so the two read identically.
  Widget _playStopButton(NarrationSegment segment, bool isPlaying) {
    final tokens = _tokens;
    final label = isPlaying
        ? _l10n.gui_narration_stop
        : _l10n.gui_narration_play;
    return AppButton(
      key: Key('segAction_${segment.index}'),
      style: AppButtonStyle.outlined,
      compact: true,
      onPressed: () => _togglePlay(segment),
      icon: Icon(
        isPlaying ? CupertinoIcons.stop_circle : CupertinoIcons.play_fill,
        size: 14,
        color: tokens.colors.textPrimary,
      ),
      // Reused clips explain themselves; the rest just restate the label.
      tooltip: segment.resumed ? _l10n.gui_narration_resumedTooltip : label,
      child: Text(label, style: tokens.typography.body),
    );
  }

  Widget _buildProgressBar(AppController controller) {
    final colors = _tokens.colors;
    return ProgressBar(
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
          AppButton(
            key: const Key('runActionBack'),
            onPressed: () => _onBack(),
            style: AppButtonStyle.outlined,
            child: Text(_l10n.gui_narration_back),
          ),
          const Spacer(),
          if (controller.narrating && !controller.runStopped)
            AppButton(
              key: const Key('runCancelButton'),
              onPressed: _onCancel,
              icon: const Icon(CupertinoIcons.stop),
              child: Text(_l10n.gui_narration_cancelRun),
            ),
        ],
      ),
    );
  }
}
