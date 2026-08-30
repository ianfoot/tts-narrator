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
    final def = _defaultVoiceFor(profile);
    _voice = def?.$1 ?? kDefaultProfile.voice;
    _voiceLabel = def?.$2;
  }

  final VoiceConfigLoader _loader;

  /// The compiled fish bootstrap alias is the out-of-box start; [changeModel]
  /// moves to other configured models.
  String _modelAlias = kDefaultProfile.profile.alias;
  late VoiceConfig _voiceConfig;

  // --- Model & voice ------------------------------------------------

  /// The active model profile (alias resolved against the loaded config).
  TtsModelProfile get profile => profileFor(_modelAlias, _voiceConfig) ??
      kDefaultProfile.profile;

  VoiceConfig get voiceConfig => _voiceConfig;

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

  String accent = 'southern British English, neutral and clear';
  String style = 'warm, composed, restrained, literary';
  String passagePrefix =
      'Narrate this passage for an audiobook. You are a warm, composed female narrator.';
  bool useCalmTag = false;
  int minWords = 30;
  int? sampleLen;
  String outDir = 'output';
  bool resume = false;

  /// Cost data for the active model (free until the config sets pricing).
  AudioPricing get pricing => _voiceConfig.pricingFor(profile.alias);

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

  /// Marks the start of a narration run (set by the run view).
  void startNarrating() {
    if (_narrating) return;
    _narrating = true;
    notifyListeners();
  }

  /// Clears the in-run flag (set by the run view on completion/abort).
  void stopNarrating() {
    if (!_narrating) return;
    _narrating = false;
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
      return 'Nothing to narrate yet — type or paste some text.';
    }
    if (_narrating) {
      return 'Narration is already running.';
    }
    return null;
  }
}