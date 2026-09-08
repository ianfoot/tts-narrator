import 'package:flutter/foundation.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'document_controller.dart';
import 'model_profile_voice_controller.dart';
import 'settings_controller.dart';
import '../theme/app_text_tokens.dart' show TextTokens;

/// Owns the narration-run lifecycle for the TTS Narrator GUI: the running
/// flag, the snapshotted [runConfig] + segment plan, per-segment progress,
/// cancellation, and the terminal run state (finished/stopped/error) plus the
/// combined-track path and segment cleanup.
///
/// Extracted from [AppController] so run execution stands alone. [AppController]
/// forwards this surface and re-broadcasts notifications, so callers keep a
/// single change stream.
///
/// The controller reads the open document ([DocumentController]) only to guard
/// run start against empty text, the current settings ([SettingsController])
/// only to assemble the run config at start, and the active model
/// ([ModelProfileVoiceController]) for the pricing fallback in the cost
/// estimate.
class RunController extends ChangeNotifier {
  RunController({
    required this._document,
    required this._settings,
    required this._model,
  });

  /// The open document (read only to block run start on empty text).
  final DocumentController _document;

  /// The narration settings (read only to assemble the run config at start).
  final SettingsController _settings;

  /// The active model (read only for the pricing fallback in estimates).
  final ModelProfileVoiceController _model;

  // --- Run state + command slots -------------------------------------

  bool _narrating = false;

  bool get narrating => _narrating;

  /// The config snapshot for the active run (banner reads model/voice/estimate
  /// from this), or null before a run starts.
  NarrationConfig? runConfig;

  /// Output directory of the most recent (or active) run; the target for
  /// segment cleanup. Null until a run starts.
  String? _lastRunDir;

  /// The output directory of the most recent run; [segmentCleanupAvailable]
  /// inspects this. Null before any run starts.
  String? get lastRunOutputDir => _lastRunDir;

  /// Whether the most recent run's per-segment audio files can still be
  /// cleaned up (combined track exists, segments not yet deleted, and the run
  /// is finished). Powers the File ▸ "Clean Up Segments…" command.
  bool get canCleanupSegments {
    if (narrating) return false;
    final dir = _lastRunDir;
    return dir != null && segmentCleanupAvailable(dir);
  }

  /// Deletes the last run's per-segment audio files, keeping the combined
  /// track and the manifest (marked `segments_deleted: true`). Returns how
  /// many files were removed; a later call is a harmless no-op. Guarded
  /// against running while narration is active so the tiles' completed
  /// indicators revert instead of dangling at deleted files. Throws a
  /// [FileSystemException] when a segment cannot be removed.
  Future<int> cleanupSegments() async {
    if (narrating) return 0;
    final dir = _lastRunDir;
    if (dir == null) return 0;
    final removed = cleanupSegmentFiles(dir);
    if (removed > 0) {
      for (final segment in runSegments) {
        segment.filePath = null;
      }
    }
    notifyListeners();
    return removed;
  }

  /// The segment plan for the active run; empty until [startRun] builds it.
  List<NarrationSegment> runSegments = const [];

  /// Plan failure (missing/empty text) — render this instead of a run.
  String? runPlanError;

  /// Narration failure mid-run (API/etc).
  String? runError;

  /// Absolute path of the completed combined track from the last successful
  /// run, or null until one lands. Persists across leaving the run view so the
  /// editor can keep offering playback of the finished file; cleared when a new
  /// run starts or the run state resets (cleanup keeps the track on disk).
  String? _completedAudioPath;

  String? get completedAudioPath => _completedAudioPath;

  bool _runFinished = false;
  bool _runStopped = false;

  bool get runFinished => _runFinished;

  bool get runStopped => _runStopped;

  int _doneCount = 0;

  /// Number of segments whose audio has landed on disk.
  int get runDoneCount => _doneCount;

  int get totalSegments => runSegments.length;

  double get runProgress =>
      totalSegments == 0 ? 0 : runDoneCount / totalSegments;

  double get runEstimatedMinutes =>
      estimateMinutes(runSegments.map((s) => s.paragraph).toList());

  double get runEstimatedCostUsd => estimateCostUsd(
    runConfig?.pricing ?? _model.pricing,
    runSegments.map((s) => s.paragraph).toList(),
  );

  AbortToken? _abort;

  /// Launches narration of the current document with the current settings,
  /// snapshotting the plan + config so the run view is stable even as the
  /// editor keeps changing behind it.
  ///
  /// Synchronously runs the plan (so a missing/empty text surfaces
  /// [runPlanError] without a half-started run), then narrates in the
  /// background, publishing per-segment progress via [notifyListeners]. Cancel
  /// via [cancelRun] throws [AbortException] (→ [runStopped]); any other
  /// failure lands in [runError].
  void startRun() {
    // Idempotent against callers that dispatch without the guard (menu bar).
    if (_narrating) return;
    final NarrationConfig config;
    try {
      config = _settings.buildConfig();
    } catch (e) {
      _resetRunState();
      runPlanError = e.toString();
      notifyListeners();
      return;
    }
    final List<String> paragraphs;
    try {
      paragraphs = planSegments(config);
    } catch (e) {
      _resetRunState();
      runPlanError = e.toString();
      notifyListeners();
      return;
    }
    _resetRunState();
    runConfig = config;
    _lastRunDir = outputDirPath(config);
    // narrate() processes only min(sampleLen, paragraphs.length) segments; build
    // segments from the same count so progress reaches 100% and no phantom
    // pending tiles linger past a sampled run.
    final sampleLen = config.sampleLen;
    final runCount = sampleLen == null
        ? paragraphs.length
        : (sampleLen < paragraphs.length ? sampleLen : paragraphs.length);
    runSegments = [
      for (var i = 0; i < runCount; i++)
        NarrationSegment(index: i, paragraph: paragraphs[i]),
    ];
    _narrating = true;
    _abort = AbortToken();
    notifyListeners();
    _narrate(config);
  }

  void _resetRunState() {
    runSegments = const [];
    runConfig = null;
    runPlanError = null;
    runError = null;
    _runFinished = false;
    _runStopped = false;
    _completedAudioPath = null;
    _doneCount = 0;
    _abort = null;
  }

  Future<void> _narrate(NarrationConfig config) async {
    final token = _abort!;
    // Snapshot the segment tiles this invocation owns. A successor run
    // reassigns the runSegments field before a cancelled predecessor unwinds,
    // so callbacks must drive the tiles they created — never whatever run is
    // current now.
    final segments = runSegments;
    bool isCurrentRun() => _abort == token;
    try {
      try {
        await narrate(
          config,
          abort: token,
          onProgress: (i, total, paragraph, {resumed = false}) {
            segments[i].running = true;
            notifyListeners();
          },
          onSegmentComplete: (i, filePath, {resumed = false}) {
            segments[i]
              ..running = false
              ..filePath = filePath
              ..resumed = resumed;
            if (isCurrentRun()) _doneCount++;
            notifyListeners();
          },
        );
        // Only the current run drives terminal state: a cancelled predecessor
        // that settles after a successor took over must not mark the new run
        // stopped or overwrite its completed-track path/error.
        if (isCurrentRun()) {
          if (token.cancelled) {
            _runStopped = true;
          } else {
            _runFinished = true;
            _completedAudioPath = combinedFilePath(_lastRunDir!);
          }
        }
      } on AbortException {
        if (isCurrentRun()) _runStopped = true;
      } catch (e) {
        // Includes non-Exception failures (e.g. a StateError from an
        // unregistered provider) — surface them instead of crashing the view.
        if (isCurrentRun()) runError = e.toString();
      }
    } finally {
      // Unwind unconditionally: even a non-Exception failure must not leave a
      // lingering segment spinner on the tiles this invocation owned. Post the
      // clear even when a successor run took over — the last notify before a
      // cancel happened before this flag flip, and the run view keeps painting
      // this invocation's tiles until they revert.
      for (final segment in segments) {
        segment.running = false;
      }
      notifyListeners();
      if (isCurrentRun()) {
        _narrating = false;
        _abort = null;
      }
    }
  }

  /// Requests cancellation of the active run (no-op when idle).
  void cancelRun() {
    if (!_narrating) return;
    _abort?.cancel();
    // Go idle immediately so the user can start a new run while the old
    // request unwinds; a cancelled provider's onCancel hook aborts the live
    // call, and the narrate tail's isCurrentRun guards keep a settled zombie
    // from clobbering a successor run's state. Until the provider's force-close
    // lands, a zombie may still write a late segment/manifest to the shared out
    // dir — bounded today because OpenRouter force-closes on cancel.
    _abort = null;
    _narrating = false;
    // Mark the run as stopped immediately so the run view flips UI without
    // waiting for the abort checkpoint; the narrate tail reconciles it too.
    _runStopped = true;
    notifyListeners();
  }

  /// Returns null when narration may start, otherwise the reason it is
  /// blocked (empty text / already running). The Narrate entrypoints guard on
  /// this before dispatching to the facade's [startRun].
  String? narrateBlockReason() {
    if (_document.text.trim().isEmpty) {
      return TextTokens.gui_controller_blockReasons_emptyText;
    }
    if (_narrating) {
      return TextTokens.gui_controller_blockReasons_alreadyRunning;
    }
    return null;
  }
}

/// Per-segment run state rendered by the narration screen.
class NarrationSegment {
  NarrationSegment({required this.index, required this.paragraph});

  final int index;
  final String paragraph;

  /// Set while a segment's audio is being synthesized.
  bool running = false;

  /// Absolute path once the segment's audio is on disk (null until done).
  String? filePath;

  /// Whether this segment was reused from a prior run's manifest.
  bool resumed = false;
}