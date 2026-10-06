import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../theme/app_tokens.dart' show AppThemeMode;
import 'api_key_store.dart';
import 'config_loader.dart';
import 'document_controller.dart';
import 'model_profile_voice_controller.dart';
import 'platform_commands.dart';
import 'run_controller.dart';
import 'settings_controller.dart';
import 'theme_controller.dart';

export 'run_controller.dart' show NarrationSegment;

/// Central, platform-neutral app state for the TTS Narrator GUI: the open
/// document, the narration settings, the run flag, and the [PlatformCommands]
/// the in-app controls (and, on macOS, the native menu bar) dispatch through.
///
/// The controller holds no View state; every screen derives what it needs from
/// here and subscribes via [ChangeNotifier]. Model/voice handling reuses the
/// core's config resolution so the GUI and CLI agree on defaults.
///
/// Document management lives in [DocumentController], the appearance in
/// [ThemeController], the model/voice state in [ModelProfileVoiceController],
/// the narration settings in [SettingsController], and the run lifecycle in
/// [RunController]; this controller forwards their surfaces and re-broadcasts
/// their notifications so callers keep a single change stream.
class AppController extends ChangeNotifier {
  AppController({
    UserVoiceConfigLoader? loader,
    SharedPreferences? prefs,
    ApiKeyStore? apiKeyStore,
    SpeechClient? client,
  }) : _model = ModelProfileVoiceController(loader: loader),
       _apiKeyStore = apiKeyStore ?? ApiKeyStore() {
    // Preload the OS-secure key so run-config building (synchronous) can read
    // the cached fallback; a missing host plugin or unreachable keychain is
    // treated as "no stored key" rather than a startup failure.
    unawaited(_apiKeyStore.load());
    _settings = SettingsController(
      document: _document,
      model: _model,
      prefs: prefs,
      apiKeyStore: _apiKeyStore,
    );
    _run = RunController(
      document: _document,
      settings: _settings,
      model: _model,
      client: client,
    );
    _document.addListener(_onDocumentChanged);
    _theme.addListener(_onThemeChanged);
    _settings.addListener(_onSettingsChanged);
    _run.addListener(_onRunChanged);
    _apiKeyStore.addListener(_onSettingsChanged);
  }

  /// The model & voice state (active profile, selected voice, gender filter).
  final ModelProfileVoiceController _model;

  /// The OS-secure per-provider API-key store (Keychain / Credential Manager /
  /// libsecret). The run-config fallback reads the cached
  /// [ApiKeyStore.value] synchronously; the run-setup panel manages the active
  /// provider's key through this.
  final ApiKeyStore _apiKeyStore;

  /// The provider owning the active model, or null when no model is configured.
  ///
  /// This is the name an API key is filed under, and the only thing gating the
  /// run-setup panel's API-key section: with no model there is no provider to hold
  /// a key, so the section has nothing to act on. Whether the provider *needs* a
  /// key is not consulted — the section is offered for every provider, because
  /// the user may hold a key the config does not mention, and the server, not
  /// the app, decides whether one is required.
  String? get activeProvider => _model.profile?.provider;

  /// The in-memory document (text, path, dirty flag, save/load surface).
  final DocumentController _document = DocumentController();

  /// The appearance state and its notifier.
  final ThemeController _theme = ThemeController();

  /// The narration settings and settings-panel visibility.
  late final SettingsController _settings;

  /// The narration-run lifecycle and per-run progress.
  late final RunController _run;

  /// The platform-dispatched command slots (menu bar, toolbar bindings).
  final PlatformCommands commands = PlatformCommands();

  // --- Model & voice ------------------------------------------------

  /// The active model profile (alias resolved against the loaded config), or
  /// null when no model is configured.
  TtsModelProfile? get profile => _model.profile;

  VoiceConfig get voiceConfig => _model.voiceConfig;

  /// Warnings surfaced while loading the voice config (e.g. a skipped
  /// malformed model file). Rendered as a persistent, non-fatal banner.
  List<String> get configWarnings => _model.configWarnings;

  /// The active model alias, or null when no model is configured.
  String? get modelAlias => _model.modelAlias;

  /// The app's writer for the config directory. The settings screen goes
  /// through it, so every save lands in the `user/` overlay and the downloaded
  /// files stay as they shipped.
  VoiceConfigStore get voiceConfigStore => _model.voiceConfigStore;

  /// Raw provider voice id; an empty string means "use the model default".
  String get voice => _model.voice;

  /// Friendly voice label when one was picked; null means the raw id.
  String? get voiceLabel => _model.voiceLabel;

  /// Re-reads the config directory after the settings screen wrote to it,
  /// keeping the selected model and voice.
  void reloadConfig() {
    final before = _model.modelAlias;
    _model.reloadConfig();
    // A reload that had to fall back to the default model changed the model
    // under the reader, so a voice-design override goes with it.
    if (_model.modelAlias != before) _settings.resetInstruct();
    notifyListeners();
  }

  /// Switches the active model, preserving a user-set raw voice and resetting
  /// to the new model's default voice only when the current raw voice was
  /// (or equals) the previous model's default.
  void changeModel(String alias) {
    if (alias == _model.modelAlias) return;
    _model.changeModel(alias);
    // Voice design is per-model prose: an override written for the old model
    // describes a narrator the new one would not produce.
    _settings.resetInstruct();
    notifyListeners();
  }

  /// Sets a raw voice id (free-form ids and aliases both work; unvalidated —
  /// providers add/remove voices).
  void setVoice(String rawId, {String? label}) {
    _model.setVoice(rawId, label: label);
    notifyListeners();
  }

  /// Applies a voice picked from the list, by id; [label] is display-only.
  /// Returns false (leaving the selection unchanged) when no model is active.
  bool applyVoiceId(String id, {String? label}) {
    final applied = _model.applyVoiceId(id, label: label);
    notifyListeners();
    return applied;
  }

  // --- Voice gender -------------------------------------------------

  /// The active narrator gender; [VoiceGender.neutral] is "any".
  VoiceGender get voiceGenderFilter => _model.voiceGenderFilter;

  /// Sets the narrator-gender filter. The model owns the filter's voice
  /// narrowing/auto-switch; the passage-prefix consequences (rewriting the
  /// narrator phrase for prompt-style models) are applied by
  /// [SettingsController], which owns the prefix. The model may
  /// revert an unmatched gender back to "any" ([VoiceGender.neutral]), so the
  /// prefix rewrite reads the effective filter after the write.
  set voiceGenderFilter(VoiceGender value) {
    if (value == _model.voiceGenderFilter) return;
    _model.voiceGenderFilter = value;
    _settings.applyNarratorGender(_model.voiceGenderFilter);
    notifyListeners();
  }

  /// Whether the active model takes a voice at all; false for a model that
  /// writes its voice from prose, which has nothing to pick (drives whether the
  /// voice dropdown is shown in "Model & voice").
  bool get takesVoice => _model.takesVoice;

  /// Whether the active model tags any of its voices with a gender (drives the
  /// voice-picker gender control in "Model & voice").
  bool get hasGenderTags => _model.hasGenderTags;

  /// Selectable voices for the active model, narrowed to [voiceLanguage] and
  /// [voiceGenderFilter]. Each entry is `(id, displayLabel)`: the id is the
  /// dropdown's value because it is the only thing that tells two same-named
  /// voices apart, and tagged voices get a compact ` (m)`/` (f)`/` (n)` suffix
  /// so gender is visible in the dropdown.
  List<(String, String)> get voiceItems => _model.voiceItems;

  // --- Voice language ------------------------------------------------

  /// The active model's language code (e.g. `b` for British English); null
  /// when the model declares no languages.
  String? get voiceLanguage => _model.language;

  /// Whether the active model declares a language list (drives the
  /// voice-picker language dropdown).
  bool get hasLanguages => _model.hasLanguages;

  /// Selectable languages for the active model, in declaration order. Each
  /// entry is `(code, label)`.
  List<(String, String)> get languageItems => _model.languageItems;

  /// Applies a language code, narrowing [voiceItems] to that language and
  /// re-picking a visible voice when the current one filters away. Codes the
  /// model does not declare are ignored.
  ///
  /// A code the active gender filter would leave without any voice clears that
  /// filter instead — the reader's language choice wins — so the prefix rewrite
  /// keyed on the gender has to be re-applied here, the same way the
  /// [voiceGenderFilter] setter does it.
  void applyVoiceLanguage(String code) {
    if (code == _model.language) return;
    final gender = _model.voiceGenderFilter;
    _model.applyLanguage(code);
    if (_model.voiceGenderFilter != gender) {
      _settings.applyNarratorGender(_model.voiceGenderFilter);
    }
    notifyListeners();
  }

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
    _run.dispose();
    _apiKeyStore.removeListener(_onSettingsChanged);
    _apiKeyStore.dispose();
    super.dispose();
  }

  // --- Run setup panel -----------------------------------------------

  /// Whether the run-setup panel is shown on the editor. Driven by the toolbar
  /// toggle and, on macOS, the View menu command, so both dispatch through one
  /// piece of state.
  bool get runSetupPanelVisible => _settings.runSetupPanelVisible;

  /// Flips [runSetupPanelVisible] and notifies listeners.
  void toggleRunSetupPanel() => _settings.toggleRunSetupPanel();

  // --- API key (secure store) --------------------------------------

  /// The OS-secure key store backing the run-setup panel's "API key" section.
  ApiKeyStore get apiKeyStore => _apiKeyStore;

  /// Where the active model's API key comes from (config / env / keychain /
  /// none), mirroring the run-config precedence.
  ApiKeySource get apiKeySource => _settings.apiKeySource;

  /// Whether the active provider currently has a key in the OS secure store
  /// (enables the rail's Remove button). False when no model is configured.
  bool get hasStoredApiKey {
    final provider = activeProvider;
    return provider != null && _apiKeyStore.value(provider) != null;
  }

  /// Saves [key] for the active provider and re-broadcasts so the rail's
  /// status line updates. Throws an [ArgumentError] for an empty key.
  ///
  /// A no-op when no model is configured: there is no provider to file the key
  /// under, and the rail hides the section in that case.
  Future<void> saveApiKey(String key) async {
    final provider = activeProvider;
    if (provider == null) return;
    await _apiKeyStore.save(provider, key);
    notifyListeners();
  }

  /// Removes the active provider's stored key (if any) and re-broadcasts. A
  /// no-op when no model is configured.
  Future<void> removeApiKey() async {
    final provider = activeProvider;
    if (provider == null) return;
    await _apiKeyStore.remove(provider);
    notifyListeners();
  }

  // --- Narration settings ---------------------------------------

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

  /// Voice-design prose for a model that takes an `instruct` field; empty for
  /// every other model. Prefilled from the model's `default_instruct`.
  String get instruct => _settings.instruct;

  set instruct(String value) {
    _settings.instruct = value;
  }

  /// Speech-rate multiplier (1.0 = normal, clamped 0.25-2.0 by
  /// [SettingsController.speed]).
  double get speed => _settings.speed;

  set speed(double value) {
    _settings.speed = value;
  }

  /// Minimum words per segment (clamped to the run-setup panel's 10-100 slider
  /// range). Changing it revises the live segment plan and estimate the editor
  /// shows.
  int get minWords => _settings.minWords;

  set minWords(int value) {
    _settings.minWords = value;
  }

  /// Whether to narrate the whole document as a single TTS call instead of
  /// segmenting it. When true, [minWords] is ignored and the run-setup panel
  /// hides the "Min words per segment" control.
  bool get sendWholeFile => _settings.sendWholeFile;

  set sendWholeFile(bool value) {
    _settings.sendWholeFile = value;
  }

  /// Whether the current document is small enough for whole-file narration
  /// (see `maxWholeFileLength` in the core). The run-setup panel hides the "Send
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

  /// The UI locale, or null to follow the platform. Read by both app shells to
  /// pin `CupertinoApp.locale`.
  Locale? get locale => _settings.locale;

  set locale(Locale? value) => _settings.locale = value;

  set resume(bool value) {
    _settings.resume = value;
  }

  /// The output formats the active model declares, in its own order.
  List<TtsAudioFormat> get outputFormats => _settings.outputFormats;

  /// Whether the active model offers more than one output format, i.e. whether
  /// the run-setup panel shows the format choice at all.
  bool get outputFormatChoiceAvailable => _settings.outputFormatChoiceAvailable;

  /// The format the next run writes, for the active model.
  TtsAudioFormat get outputFormat => _settings.outputFormat;

  set outputFormat(TtsAudioFormat value) {
    _settings.outputFormat = value;
  }

  /// Cost data for the active model (free until the config sets pricing).
  AudioPricing get pricing => _model.pricing;

  /// The editable GUI options for the active model, derived from the
  /// capabilities it declares in its config file. Empty when it declares none —
  /// the app has no per-model UI knowledge of its own.
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

  String? get documentName => _document.documentName;

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

  /// Forwards a [RunController] notification.
  void _onRunChanged() {
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

  // --- Run state ----------------------------------------------------

  bool get narrating => _run.narrating;

  /// The config snapshot for the active run (banner reads model/voice/estimate
  /// from this), or null before a run starts.
  NarrationConfig? get runConfig => _run.runConfig;

  /// The output directory of the most recent run; [segmentCleanupAvailable]
  /// inspects this. Null before any run starts.
  String? get lastRunOutputDir => _run.lastRunOutputDir;

  /// Whether the most recent run's per-segment audio files can still be
  /// cleaned up (combined track exists, segments not yet deleted, and the run
  /// is finished). Powers the File ▸ "Clean Up Segments…" command.
  bool get canCleanupSegments => _run.canCleanupSegments;

  /// Deletes the last run's per-segment audio files, keeping the combined
  /// track and the manifest (marked `segments_deleted: true`). Returns how
  /// many files were removed; a later call is a harmless no-op. Guarded
  /// against running while narration is active so the tiles' completed
  /// indicators revert instead of dangling at deleted files. Throws a
  /// [FileSystemException] when a segment cannot be removed.
  Future<int> cleanupSegments() => _run.cleanupSegments();

  /// The segment plan for the active run; empty until [startRun] builds it.
  /// The list is mutable and shared with [RunController]; in-place edits are
  /// visible to both.
  List<NarrationSegment> get runSegments => _run.runSegments;

  /// Plan failure (missing/empty text) — render this instead of a run.
  String? get runPlanError => _run.runPlanError;

  /// Narration failure mid-run (API/etc).
  String? get runError => _run.runError;

  /// Absolute path of the completed combined track from the last successful
  /// run, or null until one lands. Persists across leaving the run view so the
  /// editor can keep offering playback of the finished file; cleared when a new
  /// run starts or the run state resets (cleanup keeps the track on disk).
  String? get completedAudioPath => _run.completedAudioPath;

  bool get runFinished => _run.runFinished;

  bool get runStopped => _run.runStopped;

  /// Number of segments whose audio has landed on disk.
  int get runDoneCount => _run.runDoneCount;

  int get totalSegments => _run.totalSegments;

  double get runProgress => _run.runProgress;

  double get runEstimatedMinutes => _run.runEstimatedMinutes;

  double get runEstimatedCostUsd => _run.runEstimatedCostUsd;

  /// Launches narration of the current document with the current settings,
  /// snapshotting the plan + config so the run view is stable even as the
  /// editor keeps changing behind it.
  ///
  /// Synchronously runs the plan (so a missing/empty text surfaces
  /// [runPlanError] without a half-started run), then narrates in the
  /// background, publishing per-segment progress via the re-broadcast stream.
  /// Cancel via [cancelRun] throws [AbortException] (→ [runStopped]); any other
  /// failure lands in [runError]. Delegated to [RunController].
  void startRun() => _run.startRun();

  /// Requests cancellation of the active run (no-op when idle).
  void cancelRun() => _run.cancelRun();

  /// Opens the native directory picker for the output destination; leaves the
  /// current directory unchanged when cancelled or when the picker fails.
  Future<void> pickOutputFolder() => _settings.pickOutputFolder();

  /// Returns null when narration may start, otherwise the reason it is
  /// blocked (empty text / already running). The Narrate entrypoints guard on
  /// this before dispatching to [PlatformCommands.onNarrate].
  NarrationBlockReason? narrateBlockReason() => _run.narrateBlockReason();

  /// Clears the document text. Disabled when no text or while narrating.
  /// Saves current text to undo stack before clearing.
  void clearText() {
    if (!canClearText) return; // Centralized guard
    // Save to undo stack before clearing
    _undoStack.add(text);
    // Keep only last 10 for memory
    if (_undoStack.length > 10) _undoStack.removeAt(0);
    _document.clearText();
  }

  /// Undo the last clear action.
  void undoClear() {
    if (_undoStack.isNotEmpty) {
      final restored = _undoStack.removeLast();
      _document.setText(restored);
    }
  }

  /// Whether undo is available.
  bool get canUndoClear => _undoStack.isNotEmpty;

  final List<String> _undoStack = [];

  /// Whether the clear action should be enabled (text non-empty, not narrating).
  bool get canClearText => text.isNotEmpty && !narrating;
}
