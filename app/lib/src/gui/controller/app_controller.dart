import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'config_loader.dart';
import 'document_controller.dart';
import 'model_profile_voice_controller.dart';
import 'settings_controller.dart';
import 'theme_controller.dart';
import '../theme/app_text_tokens.dart' show TextTokens;
import '../theme/app_tokens.dart' show AppThemeMode;

/// Central, platform-neutral app state for the TTS Narrator GUI: the open
/// document, the narration settings, the run flag, and the command slots that
/// the in-app controls (and, on macOS, the native menu bar) dispatch through.
///
/// The controller holds no View state; every screen derives what it needs from
/// here and subscribes via [ChangeNotifier]. Model/voice handling reuses the
/// core's config resolution so the GUI and CLI agree on defaults.
///
/// Document management lives in [DocumentController], the appearance in
/// [ThemeController], the model/voice state in [ModelProfileVoiceController],
/// and the narration settings in [SettingsController]; this
/// controller forwards their surfaces and re-broadcasts their notifications so
/// callers keep a single change stream.
class AppController extends ChangeNotifier {
  AppController({VoiceConfigLoader? loader, SharedPreferences? prefs})
    : _model = ModelProfileVoiceController(loader: loader) {
    _settings = SettingsController(
      document: _document,
      model: _model,
      prefs: prefs,
    );
    _document.addListener(_onDocumentChanged);
    _theme.addListener(_onThemeChanged);
    _settings.addListener(_onSettingsChanged);
  }

  /// The model & voice state (active profile, selected voice, gender filter).
  final ModelProfileVoiceController _model;

  /// The in-memory document (text, path, dirty flag, save/load surface).
  final DocumentController _document = DocumentController();

  /// The appearance state and its notifier.
  final ThemeController _theme = ThemeController();

  /// The narration settings and settings-panel visibility.
  late final SettingsController _settings;

  // --- Model & voice ------------------------------------------------

  /// The active model profile (alias resolved against the loaded config).
  TtsModelProfile get profile => _model.profile;

  VoiceConfig get voiceConfig => _model.voiceConfig;

  /// Warnings surfaced while loading the voice config (e.g. a skipped
  /// malformed model file). Rendered as a persistent, non-fatal banner.
  List<String> get configWarnings => _model.configWarnings;

  String get modelAlias => _model.modelAlias;

  /// Raw provider voice id; an empty string means "use the model default".
  String get voice => _model.voice;

  /// Friendly voice label when one was picked; null means the raw id.
  String? get voiceLabel => _model.voiceLabel;

  /// Switches the active model, preserving a user-set raw voice and resetting
  /// to the new model's default voice only when the current raw voice was
  /// (or equals) the previous model's default.
  void changeModel(String alias) {
    if (alias == _model.modelAlias) return;
    _model.changeModel(alias);
    notifyListeners();
  }

  /// Sets a raw voice id (free-form ids and aliases both work; unvalidated —
  /// providers add/remove voices).
  void setVoice(String rawId, {String? label}) {
    _model.setVoice(rawId, label: label);
    notifyListeners();
  }

  /// Applies a friendly voice alias; resolves it to the provider raw id.
  void applyVoiceLabel(String label) {
    _model.applyVoiceLabel(label);
    notifyListeners();
  }

  // --- Voice gender -------------------------------------------------

  /// The active narrator gender, or null for "any".
  VoiceGender? get voiceGenderFilter => _model.voiceGenderFilter;

  /// Sets the narrator-gender filter. The model owns the filter's voice
  /// narrowing/auto-switch; the passage-prefix consequences (rewriting the
  /// narrator phrase for prompt-style models) are applied by
  /// [SettingsController], which owns the prefix. The model may
  /// revert an unmatched gender back to null, so the prefix rewrite reads the
  /// effective filter after the write.
  set voiceGenderFilter(VoiceGender? value) {
    if (value == _model.voiceGenderFilter) return;
    _model.voiceGenderFilter = value;
    _settings.applyNarratorGender(_model.voiceGenderFilter);
    notifyListeners();
  }

  /// Whether the active model tags any of its voices with a gender (drives the
  /// voice-picker gender control in "Model & voice").
  bool get hasGenderTags => _model.hasGenderTags;

  /// Selectable voices for the active model, narrowed to [voiceGenderFilter].
  /// Each entry is `(value, displayLabel)`: tagged voices get a compact
  /// ` (m)`/` (f)`/` (n)` suffix so gender is visible in the dropdown.
  List<(String, String)> get voiceItems => _model.voiceItems;

  // --- Appearance ----------------------------------------------------

  /// The user's appearance choice ([AppThemeMode.system] follows the OS).
  /// Session-only; defaults to the OS setting so the app boots as before.
  ///
  /// Backed by [themeNotifier] so appearance-only widgets (e.g. the app root
  /// theme resolution) can subscribe without rebuilding on every other
  /// controller write; the [ChangeNotifier] notification is still fired for
  /// widgets that display the current label.
  AppThemeMode get themeMode => _theme.themeMode;

  /// Fires when [themeMode] changes. Subscribe here (not the whole
  /// controller) for widgets that depend only on the appearance.
  ValueNotifier<AppThemeMode> get themeNotifier => _theme.themeNotifier;

  set themeMode(AppThemeMode value) {
    _theme.themeMode = value;
  }

  @override
  void dispose() {
    _document.dispose();
    _theme.dispose();
    _model.dispose();
    _settings.dispose();
    super.dispose();
  }

  // --- Settings panel -----------------------------------------------

  /// Whether the settings rail is shown on the editor. Driven by the toolbar
  /// toggle and, on macOS, the View menu command, so both dispatch through one
  /// piece of state.
  bool get settingsPanelVisible => _settings.settingsPanelVisible;

  /// Flips [settingsPanelVisible] and notifies listeners.
  void toggleSettingsPanel() => _settings.toggleSettingsPanel();

  // --- Narration settings -------------------------------------------

  String get accent => _settings.accent;

  set accent(String value) {
    _settings.accent = value;
  }

  String get style => _settings.style;

  set style(String value) {
    _settings.style = value;
  }

  String get passagePrefix => _settings.passagePrefix;

  set passagePrefix(String value) {
    _settings.passagePrefix = value;
  }

  bool get useCalmTag => _settings.useCalmTag;

  set useCalmTag(bool value) {
    _settings.useCalmTag = value;
  }

  /// Minimum words per segment (clamped to the settings rail's 10-100 slider
  /// range). Changing it revises the live segment plan and estimate the editor
  /// shows.
  int get minWords => _settings.minWords;

  set minWords(int value) {
    _settings.minWords = value;
  }

  /// Whether to narrate the whole document as a single TTS call instead of
  /// segmenting it. When true, [minWords] is ignored and the settings rail
  /// hides the "Min words per segment" control.
  bool get sendWholeFile => _settings.sendWholeFile;

  set sendWholeFile(bool value) {
    _settings.sendWholeFile = value;
  }

  /// Whether the current document is small enough for whole-file narration
  /// (see `maxWholeFileLength` in the core). The settings rail hides the "Send
  /// whole file" toggle when false (documents over the cap).
  bool get wholeFileAvailable => _settings.wholeFileAvailable;

  int? get sampleLen => _settings.sampleLen;

  set sampleLen(int? value) {
    _settings.sampleLen = value;
  }

  String get outDir => _settings.outDir;

  set outDir(String value) {
    _settings.outDir = value;
  }

  bool get resume => _settings.resume;

  set resume(bool value) {
    _settings.resume = value;
  }

  /// Cost data for the active model (free until the config sets pricing).
  AudioPricing get pricing => _model.pricing;

  /// The editable GUI options for the active model, declared by its model's
  /// plugin (the provider package). Empty when no plugin declares a spec — the
  /// app has no per-model UI knowledge.
  ModelUiSpec get modelUiSpec => _model.modelUiSpec;

  /// Assembles the run config for the current document + settings, narrating
  /// from the in-memory [text] (`sourceText`) so typed/pasted content needs no
  /// backing file. [inputPath] drives only output naming.
  ///
  /// Throws a [FormatException] when the active model has no voice selected and
  /// no config default (mirrors the CLI's error).
  NarrationConfig buildConfig() => _settings.buildConfig();

  // --- Document ------------------------------------------------------

  /// The in-memory document text (typed/pasted content lives here only; a
  /// backing file is not required). Forwarded to [DocumentController].
  String get text => _document.text;

  /// Absolute path of the open document, or null for an in-memory `untitled`
  /// document.
  String? get documentPath => _document.documentPath;

  /// Whether the document has unsaved edits (load sets false; every text edit
  /// sets it true).
  bool get dirty => _document.dirty;

  String get documentName => _document.documentName;

  /// Replaces the document text (typing/paste path). Marks the document dirty.
  void setText(String value) => _document.setText(value);

  /// Loads a `.txt` document from [path], replacing the in-memory text. Clears
  /// the dirty flag. Throws a [FileSystemException] when the file is missing.
  void loadFromFile(String path) => _document.loadFromFile(path);

  /// Whole-file narration is only offered up to `maxWholeFileLength` chars; a
  /// larger document would be an unbounded single TTS call. Delegated to
  /// [SettingsController] so a document that grows past the cap (or is loaded
  /// oversized) drops the toggle instead of leaving it silently "on" and
  /// planning a giant segment.
  void _clearWholeFileIfTooLarge() => _settings.adjustWholeFileForDocument();

  /// Forwards a [DocumentController] notification: re-checks the whole-file
  /// cap, then re-broadcasts so callers keep a single change stream.
  void _onDocumentChanged() {
    _clearWholeFileIfTooLarge();
    notifyListeners();
  }

  /// Forwards a [ThemeController] notification.
  void _onThemeChanged() {
    notifyListeners();
  }

  /// Forwards a [SettingsController] notification.
  void _onSettingsChanged() {
    notifyListeners();
  }

  /// Resolves a destination for Save As (and the first save of an untitled
  /// document); returns null when the user cancels. Wired by the platform
  /// shell to the native save picker — platform-neutral so Linux/Windows bind
  /// their own picker.
  Future<String?> Function()? get saveLocationPicker =>
      _document.saveLocationPicker;

  set saveLocationPicker(Future<String?> Function()? value) {
    _document.saveLocationPicker = value;
  }

  /// Writes [text] to [path] and adopts it as the document: the dirty flag
  /// clears and future saves keep that path. Throws a [FileSystemException]
  /// when the file cannot be written.
  void saveTo(String path) => _document.saveTo(path);

  /// Saves to the current document path, or prompts (via [saveAs]) when the
  /// document has not been saved yet. Swallows write errors the way the open
  /// path does.
  Future<void> save() => _document.save();

  /// Prompts for a save location and writes the text there, adopting the new
  /// path. The old path stays intact until the user confirms a location.
  Future<void> saveAs() => _document.saveAs();

  // --- Live document stats / estimate --------------------------------

  /// Non-whitespace words in the document.
  int get wordCount => _document.wordCount;

  int get charCount => _document.charCount;

  /// The segment plan for the current text (min-word merge + length split).
  /// When [sendWholeFile] is on, the whole text is a single segment (empty
  /// when the document is blank, mirroring the empty plan the core reports).
  List<String> get plannedSegments => _settings.plannedSegments;

  double get estimatedMinutes => _settings.estimatedMinutes;

  double get estimatedCostUsd => _settings.estimatedCostUsd;

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
  List<NarrationRunSegment> runSegments = const [];

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
    runConfig?.pricing ?? pricing,
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
      config = buildConfig();
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
        NarrationRunSegment(index: i, paragraph: paragraphs[i]),
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

  /// Command slots wired by the platform shell (and later the macOS menu bar):
  /// platform-neutral command state so Linux/Windows can bind the same actions
  /// to in-app menus.
  VoidCallback? onOpen;
  VoidCallback? onNarrate;
  VoidCallback? onCancel;
  VoidCallback? onPreferences;

  /// Fired to toggle the settings panel (the native menu bar's View command
  /// dispatches here). Wired by the platform shell to [toggleSettingsPanel];
  /// mirrors the other command slots so non-macOS platforms can bind the same
  /// action to an in-app control.
  VoidCallback? onToggleSettingsPanel;

  /// Invoked to choose the output folder (opened from the native menu bar or
  /// an in-app shortcut). Wired by the platform shell; the menu item and any
  /// key binding dispatch here.
  VoidCallback? onSetOutputFolder;

  /// Opens the native directory picker for the output destination; leaves the
  /// current directory unchanged when cancelled or when the picker fails.
  Future<void> pickOutputFolder() => _settings.pickOutputFolder();

  /// Returns null when narration may start, otherwise the reason it is
  /// blocked (empty text / already running). The Narrate entrypoints guard on
  /// this before dispatching to [onNarrate].
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
class NarrationRunSegment {
  NarrationRunSegment({required this.index, required this.paragraph});

  final int index;
  final String paragraph;

  /// Set while a segment's audio is being synthesized.
  bool running = false;

  /// Absolute path once the segment's audio is on disk (null until done).
  String? filePath;

  /// Whether this segment was reused from a prior run's manifest.
  bool resumed = false;
}
