import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'config_loader.dart';

/// Central, platform-neutral app state for the TTS Narrator GUI: the open
/// document, the narration settings, the run flag, and the command slots that
/// the in-app controls (and, on macOS, the native menu bar) dispatch through.
///
/// The controller holds no View state; every screen derives what it needs from
/// here and subscribes via [ChangeNotifier]. Model/voice handling reuses the
/// core's config resolution so the GUI and CLI agree on defaults.
class AppController extends ChangeNotifier {
  AppController({VoiceConfigLoader? loader}) : _loader = loader ?? VoiceConfigLoader() {
    _voiceConfig = _loader.load();
    _modelAlias = defaultModelFor(_voiceConfig).alias;
    final def = _defaultVoiceFor(profile);
    _voice = def?.$1 ?? kDefaultProfile.voice;
    _voiceLabel = def?.$2;
  }

  final VoiceConfigLoader _loader;

  /// The preset default model (fish's compiled bootstrap unless `default_model`
  /// in the config names another); [changeModel] moves to other configured
  /// models.
  late String _modelAlias;
  late VoiceConfig _voiceConfig;

  // --- Model & voice ------------------------------------------------

  /// The active model profile (alias resolved against the loaded config).
  TtsModelProfile get profile => profileFor(_modelAlias, _voiceConfig) ??
      kDefaultProfile.profile;

  VoiceConfig get voiceConfig => _voiceConfig;

  /// Warnings surfaced while loading the voice config (e.g. a skipped
  /// malformed model file). Rendered as a persistent, non-fatal banner.
  List<String> get configWarnings => _loader.warnings;

  String get modelAlias => _modelAlias;

  /// Raw provider voice id; an empty string means "use the model default".
  String _voice = kDefaultProfile.voice;

  /// Friendly voice label when one was picked; null means the raw id.
  String? _voiceLabel = kDefaultProfile.voiceLabel;

  String get voice => _voice;

  String? get voiceLabel => _voiceLabel;

  /// Default voice for [model] from the config, or the compiled fish bootstrap
  /// for fish; null when the model has no default configured.
  (String, String)? _defaultVoiceFor(TtsModelProfile model) {
    try {
      return defaultVoiceFor(model, _voiceConfig);
    } on VoiceConfigError {
      return null;
    }
  }

  /// Switches the active model, preserving a user-set raw voice and resetting
  /// to the new model's default voice only when the current raw voice was
  /// (or equals) the previous model's default.
  void changeModel(String alias) {
    if (alias == _modelAlias) return;
    final next = profileFor(alias, _voiceConfig);
    if (next == null) return;
    final previousDefaultsTo = _defaultVoiceFor(profile)?.$1;
    if (_voice.isEmpty || _voice == previousDefaultsTo) {
      final def = _defaultVoiceFor(next);
      _voice = def?.$1 ?? '';
      _voiceLabel = def?.$2;
    } else {
      // A user-set raw voice survives the switch; the previous model's
      // friendly label no longer describes that id, so drop it.
      _voiceLabel = null;
    }
    _modelAlias = alias;
    notifyListeners();
  }

  /// Sets a raw voice id (free-form ids and aliases both work; unvalidated —
  /// providers add/remove voices).
  void setVoice(String rawId, {String? label}) {
    _voice = rawId.trim();
    _voiceLabel = (label != null && label != _voice) ? label : null;
    notifyListeners();
  }

  /// Applies a friendly voice alias; resolves it to the provider raw id.
  void applyVoiceLabel(String label) {
    final (id, _) = _voiceConfig.resolveVoice(profile.alias, label);
    setVoice(id, label: label);
  }

  // --- Narration settings -------------------------------------------

  String _accent = 'southern British English, neutral and clear';
  bool _useCalmTag = false;
  int _minWords = 30;
  int? _sampleLen;
  String _outDir = 'output';
  bool _resume = false;
  String _style = 'warm, composed, restrained, literary';
  String _passagePrefix =
      'Narrate this passage for an audiobook. You are a warm, composed female narrator.';

  String get accent => _accent;

  set accent(String value) {
    if (value == _accent) return;
    _accent = value;
    notifyListeners();
  }

  String get style => _style;

  set style(String value) {
    if (value == _style) return;
    _style = value;
    notifyListeners();
  }

  String get passagePrefix => _passagePrefix;

  set passagePrefix(String value) {
    if (value == _passagePrefix) return;
    _passagePrefix = value;
    notifyListeners();
  }

  bool get useCalmTag => _useCalmTag;

  set useCalmTag(bool value) {
    if (value == _useCalmTag) return;
    _useCalmTag = value;
    notifyListeners();
  }

  /// Minimum words per segment (clamped to the settings rail's 10-100
  /// slider range). Changing it revises the live chunk plan and estimate the
  /// editor shows.
  int get minWords => _minWords;

  set minWords(int value) {
    final clamped = value.clamp(10, 100);
    if (clamped == _minWords) return;
    _minWords = clamped;
    notifyListeners();
  }

  int? get sampleLen => _sampleLen;

  set sampleLen(int? value) {
    if (value == _sampleLen) return;
    _sampleLen = value;
    notifyListeners();
  }

  String get outDir => _outDir;

  set outDir(String value) {
    if (value == _outDir) return;
    _outDir = value;
    notifyListeners();
  }

  bool get resume => _resume;

  set resume(bool value) {
    if (value == _resume) return;
    _resume = value;
    notifyListeners();
  }

  /// Cost data for the active model (free until the config sets pricing).
  AudioPricing get pricing => _voiceConfig.pricingFor(profile.alias);

  /// The editable GUI options for the active model, declared by its model's
  /// plugin (the provider package). Empty when no plugin declares a spec — the
  /// app has no per-model UI knowledge.
  ModelUiSpec get modelUiSpec =>
      ttsProviderRegistry.resolveOrNull(profile.provider)?.modelUiSpecFor(
            profile,
          ) ??
      const ModelUiSpec.empty();

  /// Assembles the run config for the current document + settings, narrating
  /// from the in-memory [text] (`sourceText`) so typed/pasted content needs no
  /// backing file. [inputPath] drives only output naming.
  ///
  /// Throws a [FormatException] when the active model has no voice selected and
  /// no config default (mirrors the CLI's error).
  NarrationConfig buildConfig() {
    final p = profile;
    final raw = _voice.trim();
    String voiceId;
    String? label;
    if (raw.isEmpty) {
      final def = _defaultVoiceFor(p);
      if (def == null) {
        throw FormatException(
          'No voice selected for "${p.alias}" — pick an alias or set a '
          'default in the voice config.',
        );
      }
      voiceId = def.$1;
      label = def.$2 == def.$1 ? null : def.$2;
    } else {
      final (id, resolvedLabel) = _voiceConfig.resolveVoice(p.alias, raw);
      voiceId = id;
      label = (_voiceLabel != null && id == raw)
          ? _voiceLabel
          : (resolvedLabel != id ? resolvedLabel : null);
    }
    return NarrationConfig(
      inputPath: _documentPath ?? 'untitled.txt',
      sourceText: _text,
      profile: p,
      voice: voiceId,
      voiceLabel: label,
      accent: accent,
      style: style,
      useCalmTag: useCalmTag,
      passagePrefix: passagePrefix,
      minWords: minWords,
      sampleLen: sampleLen,
      outDir: outDir.trim().isEmpty ? 'output' : outDir.trim(),
      resume: resume,
      providerSettings: _loader.resolveProviderSettings(p),
      pricing: _voiceConfig.pricingFor(p.alias),
    );
  }

  // --- Document ------------------------------------------------------

  String _text = '';
  String? _documentPath;
  bool _dirty = false;

  String get text => _text;

  /// Absolute path of the open document, or null for an in-memory `untitled`
  /// document.
  String? get documentPath => _documentPath;

  /// Whether the document has unsaved edits (load sets false; every text edit
  /// sets it true).
  bool get dirty => _dirty;

  String get documentName => _documentPath == null
      ? 'untitled.txt'
      : _documentPath!.split(Platform.pathSeparator).last;

  /// Replaces the document text (typing/paste path). Marks the document dirty.
  void setText(String value) {
    if (value == _text) return;
    _text = value;
    _dirty = true;
    notifyListeners();
  }

  /// Loads a `.txt` document from [path], replacing the in-memory text. Clears
  /// the dirty flag. Throws a [FileSystemException] when the file is missing.
  void loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Cannot open text file', path);
    }
    _text = file.readAsStringSync();
    _documentPath = file.absolute.path;
    _dirty = false;
    notifyListeners();
  }

  /// Resolves a destination for Save As (and the first save of an untitled
  /// document); returns null when the user cancels. Wired by the platform
  /// shell to the native save picker — platform-neutral so Linux/Windows bind
  /// their own picker.
  Future<String?> Function()? saveLocationPicker;

  /// Writes [text] to [path] and adopts it as the document: the dirty flag
  /// clears and future saves keep that path. Throws a [FileSystemException]
  /// when the file cannot be written.
  void saveTo(String path) {
    File(path).writeAsStringSync(_text);
    _documentPath = File(path).absolute.path;
    _dirty = false;
    notifyListeners();
  }

  /// Saves to the current document path, or prompts (via [saveAs]) when the
  /// document has not been saved yet. Swallows write errors the way the open
  /// path does.
  Future<void> save() async {
    if (_documentPath == null) {
      await saveAs();
      return;
    }
    try {
      saveTo(_documentPath!);
    } on FileSystemException {
      // Ignore write failures; the document stays dirty.
    }
  }

  /// Prompts for a save location and writes the text there, adopting the new
  /// path. The old path stays intact until the user confirms a location.
  Future<void> saveAs() async {
    final path = await saveLocationPicker?.call();
    if (path == null) return;
    try {
      saveTo(path);
    } on FileSystemException {
      // Ignore write failures; the document stays dirty.
    }
  }

  // --- Live document stats / estimate --------------------------------

  /// Non-whitespace words in the document.
  int get wordCount =>
      _text.trim().isEmpty ? 0 : _text.trim().split(RegExp(r'\s+')).length;

  int get charCount => _text.length;

  /// The chunk plan for the current text (min-word merge + length split).
  List<String> get plannedChunks => chunkText(_text, minWords: minWords);

  double get estimatedMinutes => estimateMinutes(plannedChunks);

  double get estimatedCostUsd => estimateCostUsd(pricing, plannedChunks);

  // --- Run state + command slots -------------------------------------

  bool _narrating = false;

  bool get narrating => _narrating;

  /// The config snapshot for the active run (banner reads model/voice/estimate
  /// from this), or null before a run starts.
  NarrationConfig? runConfig;

  /// The chunk plan for the active run; empty until [startRun] builds it.
  List<NarrationRunChunk> runChunks = const [];

  /// Plan failure (missing/empty text) — render this instead of a run.
  String? runPlanError;

  /// Narration failure mid-run (API/etc).
  String? runError;

  bool _runFinished = false;
  bool _runStopped = false;

  bool get runFinished => _runFinished;

  bool get runStopped => _runStopped;

  int _doneCount = 0;

  /// Number of chunks whose audio has landed on disk.
  int get runDoneCount => _doneCount;

  int get totalChunks => runChunks.length;

  double get runProgress => totalChunks == 0 ? 0 : runDoneCount / totalChunks;

  double get runEstimatedMinutes =>
      estimateMinutes(runChunks.map((c) => c.paragraph).toList());

  double get runEstimatedCostUsd =>
      estimateCostUsd(runConfig?.pricing ?? pricing, runChunks.map((c) => c.paragraph).toList());

  AbortToken? _abort;

  /// Launches narration of the current document with the current settings,
  /// snapshotting the plan + config so the run view is stable even as the
  /// editor keeps changing behind it.
  ///
  /// Synchronously runs the plan (so a missing/empty text surfaces
  /// [runPlanError] without a half-started run), then narrates in the
  /// background, publishing per-chunk progress via [notifyListeners]. Cancel
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
      paragraphs = planChunks(config);
    } catch (e) {
      _resetRunState();
      runPlanError = e.toString();
      notifyListeners();
      return;
    }
    _resetRunState();
    runConfig = config;
    // narrate() processes only min(sampleLen, paragraphs.length) chunks; build
    // chunks from the same count so progress reaches 100% and no phantom
    // pending tiles linger past a sampled run.
    final sampleLen = config.sampleLen;
    final runCount = sampleLen == null
        ? paragraphs.length
        : (sampleLen < paragraphs.length ? sampleLen : paragraphs.length);
    runChunks = [
      for (var i = 0; i < runCount; i++)
        NarrationRunChunk(index: i, paragraph: paragraphs[i]),
    ];
    _narrating = true;
    _abort = AbortToken();
    notifyListeners();
    _narrate(config);
  }

  void _resetRunState() {
    runChunks = const [];
    runConfig = null;
    runPlanError = null;
    runError = null;
    _runFinished = false;
    _runStopped = false;
    _doneCount = 0;
    _abort = null;
  }

  Future<void> _narrate(NarrationConfig config) async {
    final token = _abort!;
    try {
      try {
        await narrate(
          config,
          abort: token,
          onProgress: (i, total, paragraph, {resumed = false}) {
            runChunks[i].running = true;
            notifyListeners();
          },
          onChunkComplete: (i, filePath, {resumed = false}) {
            runChunks[i]..running = false..filePath = filePath..resumed = resumed;
            _doneCount++;
            notifyListeners();
          },
        );
        if (token.cancelled) {
          _runStopped = true;
        } else {
          _runFinished = true;
        }
      } on AbortException {
        _runStopped = true;
      } catch (e) {
        // Includes non-Exception failures (e.g. a StateError from an
        // unregistered provider) — surface them instead of crashing the view.
        runError = e.toString();
      }
    } finally {
      // Unwind unconditionally: even a non-Exception failure must not leave
      // the controller "already running" forever. Also stop any in-flight
      // chunk spinner so the run view shows a clean stopped/failed state.
      for (final chunk in runChunks) {
        chunk.running = false;
      }
      _narrating = false;
      _abort = null;
      notifyListeners();
    }
  }

  /// Requests cancellation of the active run (no-op when idle).
  void cancelRun() {
    if (!_narrating) return;
    _abort?.cancel();
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

  /// Returns null when narration may start, otherwise the reason it is
  /// blocked (empty text / already running). The Narrate entrypoints guard on
  /// this before dispatching to [onNarrate].
  String? narrateBlockReason() {
    if (_text.trim().isEmpty) {
      return 'Editor text is empty';
    }
    if (_narrating) {
      return 'Narration is already running.';
    }
    return null;
  }
}

/// Per-chunk run state rendered by the narration screen.
class NarrationRunChunk {
  NarrationRunChunk({required this.index, required this.paragraph});

  final int index;
  final String paragraph;

  /// Set while a chunk's audio is being synthesized.
  bool running = false;

  /// Absolute path once the chunk's audio is on disk (null until done).
  String? filePath;

  /// Whether this chunk was reused from a prior run's manifest.
  bool resumed = false;
}