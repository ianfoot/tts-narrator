import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'document_controller.dart';
import 'api_key_store.dart';
import 'controller_errors.dart';
import 'model_profile_voice_controller.dart';

/// Where the effective API key for the active model's provider comes from.
enum ApiKeySource {
  /// No key configured anywhere.
  missing,

  /// Stored in the OS secure store (Keychain / Credential Manager / libsecret).
  keychain,

  /// A literal value in the `providers.<id>` config block.
  config,

  /// A `${ENV}` reference in the config resolved from the runtime environment.
  environment,
}

/// Owns the narration settings and the editor's settings-panel visibility for
/// the TTS Narrator GUI: accent/style, passage prefix, per-segment sizing,
/// whole-file/sample/out-dir/resume toggles, and the output folder persisted
/// through [SharedPreferences].
///
/// Extracted from [AppController] so the settings surface stands alone.
/// [AppController] forwards these getters/setters and re-broadcasts
/// notifications, so callers keep a single change stream.
///
/// The controller reads the open document ([DocumentController]) when the
/// editor derives whole-file availability or the live segment plan, and the
/// active model ([ModelProfileVoiceController]) when assembling the run config
/// via [buildConfig] or when a prompt-style model's narrator-gender filter
/// rewrites the passage prefix.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required this._document,
    required this._model,
    SharedPreferences? prefs,
    this.apiKeyStore,
  }) : _prefs = prefs {
    final savedOutDir = prefs?.getString(_outDirPrefsKey);
    if (savedOutDir != null && savedOutDir.trim().isNotEmpty) {
      _outDir = savedOutDir;
    }
    final savedLocale = prefs?.getString(_localePrefsKey);
    if (savedLocale != null && savedLocale.trim().isNotEmpty) {
      _locale = _parseLocale(savedLocale);
    }
  }

  /// Preferences key holding the last output folder the user picked.
  static const _outDirPrefsKey = 'outDir';

  /// Preferences key holding the language tag the user last selected.
  static const _localePrefsKey = 'locale';

  /// Parses a stored language tag into a [Locale], or null when it is not one
  /// this build supports (a tag left behind by a removed translation).
  static Locale? _parseLocale(String tag) {
    final code = tag.replaceAll('_', '-');
    final dash = code.indexOf('-');
    final language = dash == -1 ? code : code.substring(0, dash);
    if (language.isEmpty) return null;
    final country = dash == -1 ? null : code.substring(dash + 1);
    return country == null || country.isEmpty
        ? Locale(language)
        : Locale(language, country);
  }

  /// Folder name created under the system temp dir for the default output.
  static const _defaultOutDirName = 'tts_narrator_output';

  /// The default output folder, created on demand and always absolute.
  ///
  /// Absolute because the rendered files are handed to GStreamer-backed
  /// playback on Linux, which resolves a relative path against a working
  /// directory a packaged app does not control; the old relative `output`
  /// default only resolved because the dev launcher happened to start in a
  /// checkout containing that folder. Under the system temp dir because the
  /// rendered audio is disposable — nothing is expected to outlive the run.
  static String defaultOutDir() {
    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      '$_defaultOutDirName',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// The persistent preference store; null when the host has none (tests).
  final SharedPreferences? _prefs;

  /// The OS-secure key store backing the API-key section of the settings rail;
  /// null when the host injects none (tests) — the key simply never falls back
  /// to secure storage.
  final ApiKeyStore? apiKeyStore;

  /// The open document (read for whole-file availability and the live plan).
  final DocumentController _document;

  /// The active model (read when assembling the run config and applying the
  /// narrator-gender passage-prefix rewrite for prompt-style models).
  final ModelProfileVoiceController _model;

  // --- Settings panel -----------------------------------------------

  bool _settingsPanelVisible = true;

  /// Whether the settings rail is shown on the editor. Driven by the toolbar
  /// toggle and, on macOS, the View menu command, so both dispatch through one
  /// piece of state.
  bool get settingsPanelVisible => _settingsPanelVisible;

  /// Flips [settingsPanelVisible] and notifies listeners.
  void toggleSettingsPanel() {
    _settingsPanelVisible = !_settingsPanelVisible;
    notifyListeners();
  }

  // --- Narration settings -------------------------------------------

  // Narration defaults come from the core's English-only [PromptDefaults] —
  // they are instructions for the TTS model, not UI copy, so they are
  // deliberately not localized.
  String _accent = PromptDefaults.accent;
  int _minWords = PromptDefaults.minWords;
  bool _sendWholeFile = false;
  int? _sampleLen;
  String _outDir = defaultOutDir();
  bool _resume = false;
  String _style = PromptDefaults.style;
  String _passagePrefix = PromptDefaults.passagePrefix;
  double _speed = 1.0;

  /// Selected UI locale, or null to follow the platform's resolution against
  /// [AppLocalizations.supportedLocales].
  ///
  /// Only English is translated today, so the default is null (system-driven).
  /// The preference is persisted now so adding a second `app_xx.arb` is a data
  /// change rather than a settings-plumbing change.
  Locale? _locale;

  /// The locale the UI renders in, or null to let the platform choose.
  Locale? get locale => _locale;

  set locale(Locale? value) {
    if (value == _locale) return;
    _locale = value;
    notifyListeners();
    if (value == null) {
      _prefs?.remove(_localePrefsKey);
    } else {
      _prefs?.setString(_localePrefsKey, value.toString());
    }
  }

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

  /// Speech-rate multiplier (1.0 = normal), clamped to the settings rail's
  /// 0.25-2.0 slider range. Sent to providers via `NarrationConfig.speed`.
  double get speed => _speed;

  set speed(double value) {
    final clamped = value.clamp(0.25, 2.0);
    if (clamped == _speed) return;
    _speed = clamped;
    notifyListeners();
  }

  /// Minimum words per segment (clamped to the settings rail's 10-100
  /// slider range). Changing it revises the live segment plan and estimate the
  /// editor shows.
  int get minWords => _minWords;

  set minWords(int value) {
    final clamped = value.clamp(10, 100);
    if (clamped == _minWords) return;
    _minWords = clamped;
    notifyListeners();
  }

  /// Whether to narrate the whole document as a single TTS call instead of
  /// segmenting it. When true, [minWords] is ignored and the settings rail
  /// hides the "Min words per segment" control.
  bool get sendWholeFile => _sendWholeFile;

  set sendWholeFile(bool value) {
    if (value == _sendWholeFile) return;
    _sendWholeFile = value;
    notifyListeners();
  }

  /// The current document normalized for whole-file narration (line endings
  /// normalized, trimmed), mirroring the core's plan-time transform.
  String get _wholeFileText =>
      _document.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

  /// Whether the current document is small enough for whole-file narration
  /// (see `maxWholeFileLength` in the core). The settings rail hides the "Send
  /// whole file" toggle when false (documents over the cap).
  bool get wholeFileAvailable => _wholeFileText.length <= maxWholeFileLength;

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
    _prefs?.setString(_outDirPrefsKey, value);
  }

  bool get resume => _resume;

  set resume(bool value) {
    if (value == _resume) return;
    _resume = value;
    notifyListeners();
  }

  /// Re-checks the whole-file cap on a document change: a document that grows
  /// past `maxWholeFileLength` (or is loaded oversized) silently drops
  /// [sendWholeFile] instead of leaving the toggle "on" and planning a giant
  /// segment. The announcement of the drop rides the facade's document-change
  /// broadcast, so this method does not notify on its own.
  void adjustWholeFileForDocument() {
    if (_sendWholeFile && !wholeFileAvailable) {
      _sendWholeFile = false;
    }
  }

  // --- Gendered narrator phrase (prompt-style models) -----------------

  // The gendered narrator phrase is matched as a literal substring, so these
  // must stay byte-identical to [PromptDefaults.passagePrefix]'s wording — see
  // [PromptDefaults.assertPrefixCarriesGender].
  static const _genderFemalePhrase = PromptDefaults.femalePhrase;
  static const _genderMalePhrase = PromptDefaults.malePhrase;

  /// Whether [prefix] contains the exact male-phrase form. `female narrator`
  /// already contains `male narrator` as a substring, so a plain
  /// [String.contains] can't tell them apart; a phrase is "male" only when the
  /// female form isn't also present.
  static bool _hasMaleNarratorPhrase(String prefix) =>
      prefix.contains(_genderMalePhrase) &&
      !prefix.contains(_genderFemalePhrase);

  /// Applies the narrator phrase in [_passagePrefix] to match [gender] on a
  /// prompt-style model: `female narrator` ↔ `male narrator` when switching
  /// male, or back to the ungendered default for any other gender (female,
  /// or "any" via [VoiceGender.neutral]). Only the exact phrases are swapped
  /// — custom prefixes are left alone. The facade's gender-filter write owns
  /// the single notification, so this mutates without notifying.
  void applyNarratorGender(VoiceGender gender) {
    final p = _model.profile;
    if (p == null || !p.promptStyle) return;
    switch (gender) {
      case VoiceGender.male:
        if (_passagePrefix.contains(_genderFemalePhrase)) {
          _passagePrefix = _passagePrefix.replaceAll(
            _genderFemalePhrase,
            _genderMalePhrase,
          );
        }
        break;
      case VoiceGender.female:
      case VoiceGender.neutral:
        if (_hasMaleNarratorPhrase(_passagePrefix)) {
          _passagePrefix = _passagePrefix.replaceAll(
            _genderMalePhrase,
            _genderFemalePhrase,
          );
        }
    }
  }

  // --- API key (provider secrets) -----------------------------------

  /// OpenRouter API-key setting names, in the provider's own lookup order
  /// (`api_key` first, then `OPENROUTER_API_KEY`).
  static const _apiKeySettingNames = ['api_key', 'OPENROUTER_API_KEY'];

  /// Provider ids the app requires an API key for. Mirrors the openrouter
  /// registration in `main.dart`; other providers extend this set.
  static const _keyedProviders = {'openrouter'};

  /// Whether [settings] carries a usable (non-empty) API key under any known
  /// key-setting name.
  bool _hasUsableApiKey(Map<String, String> settings) => settings.entries.any(
    (e) => _apiKeySettingNames.contains(e.key) && e.value.trim().isNotEmpty,
  );

  /// Mirrors the core `resolveSettings` env-reference pattern so the status
  /// line and the run config can never disagree about what a value means.
  static final _envRef = RegExp(r'^\$\{(\w+)\}$');

  /// Resolves a raw config [value] to a usable key, or null when it's absent,
  /// empty, or a `${ENV}` reference the runtime environment cannot fulfil.
  /// Literals are returned (trimmed); env references are expanded from
  /// [Platform.environment] exactly as the core does.
  String? _usableApiKeyValue(String raw) {
    final match = _envRef.firstMatch(raw);
    if (match != null) {
      final resolved = Platform.environment[match.group(1)];
      return (resolved == null || resolved.trim().isEmpty) ? null : resolved;
    }
    final literal = raw.trim();
    return literal.isEmpty ? null : literal;
  }

  /// Resolves the provider settings for [profile]: config.json literals and
  /// `${ENV}` references first (via the core), then the OS-secure store, and
  /// fails early with a descriptive message when no key exists anywhere.
  ///
  /// Failing here — inside [buildConfig], which [RunController.startRun]
  /// guards — turns a missing key into a plan error before the run starts
  /// instead of a mid-run narration `StateError` from the provider.
  Map<String, String> _resolveProviderSettings(TtsModelProfile p) {
    if (!_keyedProviders.contains(p.provider)) {
      return _model.resolveProviderSettings(p);
    }
    Map<String, String>? resolved;
    try {
      resolved = _model.resolveProviderSettings(p);
    } on StateError {
      // A `${ENV}` reference the runtime cannot fulfil (the shipped starter
      // config's `${OPENROUTER_API_KEY}` under a double-click launch, for
      // instance) is treated as "no config/env key"; the secure store can
      // still provide one, so fall through and re-resolve with it injected.
      resolved = null;
    }
    if (resolved != null && _hasUsableApiKey(resolved)) return resolved;
    final stored = apiKeyStore?.value;
    if (stored == null || stored.isEmpty) {
      throw const NoApiKeyConfigured();
    }
    final retried = _model.resolveProviderSettings(
      p,
      overrides: _apiKeyOverridesWith(p, stored),
    );
    if (_hasUsableApiKey(retried)) return retried;
    throw const NoApiKeyConfigured();
  }

  /// Overrides injecting the stored [key] into [profile]'s provider block:
  /// overrides whichever key-setting names are already present (preserving the
  /// provider's native naming), else supplies `OPENROUTER_API_KEY` for a block
  /// that carries none.
  Map<String, String> _apiKeyOverridesWith(TtsModelProfile p, String key) {
    final raw = _model.rawProviderSettings(p);
    final overrides = <String, String>{};
    for (final name in _apiKeySettingNames) {
      if (raw.containsKey(name)) overrides[name] = key;
    }
    if (overrides.isEmpty) overrides['OPENROUTER_API_KEY'] = key;
    return overrides;
  }

  /// Where the active model's API key comes from, mirroring the precedence
  /// applied in [_resolveProviderSettings] (config/env first, then the secure
  /// store). Drives the settings rail's status line. [ApiKeySource.missing]
  /// when no model is active or its provider needs no key.
  ///
  /// A `${ENV}` reference that cannot resolve does NOT count as "set via the
  /// environment": the app would still fail without the secure-store key, so
  /// the status agrees with what a run would actually consume.
  ApiKeySource get apiKeySource {
    final p = _model.profile;
    if (p == null || !_keyedProviders.contains(p.provider)) {
      return ApiKeySource.missing;
    }
    final raw = _model.rawProviderSettings(p);
    for (final key in _apiKeySettingNames) {
      final value = raw[key];
      if (value == null || _usableApiKeyValue(value) == null) continue;
      return _envRef.hasMatch(value)
          ? ApiKeySource.environment
          : ApiKeySource.config;
    }
    final stored = apiKeyStore?.value;
    return (stored != null && stored.isNotEmpty)
        ? ApiKeySource.keychain
        : ApiKeySource.missing;
  }

  /// Whether no API key is configured anywhere for the active model.
  bool get apiKeyMissing => apiKeySource == ApiKeySource.missing;

  // --- Run config + live estimates ------------------------------------

  /// Assembles the run config for the current document + settings, narrating
  /// from the in-memory [DocumentController.text] (`sourceText`) so
  /// typed/pasted content needs no backing file. [inputPath] drives only
  /// output naming.
  ///
  /// Throws a [FormatException] when the active model has no voice selected and
  /// no config default (mirrors the CLI's error).
  NarrationConfig buildConfig() {
    final p = _model.profile;
    if (p == null) {
      throw const NoModelConfigured();
    }
    final raw = _model.voice.trim();
    String voiceId;
    String? label;
    if (raw.isEmpty) {
      final def = _model.defaultVoice;
      if (def == null) {
        throw NoVoiceSelected(p.alias);
      }
      voiceId = def.$1;
      label = def.$2 == def.$1 ? null : def.$2;
    } else {
      final (id, resolvedLabel) = resolveVoice(
        _model.voiceConfig,
        p.alias,
        raw,
      );
      voiceId = id;
      label = (_model.voiceLabel != null && id == raw)
          ? _model.voiceLabel
          : (resolvedLabel != id ? resolvedLabel : null);
    }
    return NarrationConfig(
      inputPath: _document.documentPath ?? untitledDocumentName,
      sourceText: _document.text,
      profile: p,
      voice: voiceId,
      voiceLabel: label,
      accent: accent,
      style: style,
      passagePrefix: passagePrefix,
      minWords: minWords,
      sendWholeFile: sendWholeFile,
      sampleLen: sampleLen,
      speed: speed,
      outDir: outDir.trim().isEmpty ? defaultOutDir() : outDir.trim(),
      resume: resume,
      providerSettings: _resolveProviderSettings(p),
      pricing: _model.pricing,
    );
  }

  /// The segment plan for the current text (min-word merge + length split).
  /// When [sendWholeFile] is on, the whole text is a single segment (empty
  /// when the document is blank, mirroring the empty plan the core reports).
  List<String> get plannedSegments {
    if (sendWholeFile) {
      final whole = _wholeFileText;
      return whole.isEmpty ? const [] : [whole];
    }
    return segmentText(_document.text, minWords: minWords);
  }

  double get estimatedMinutes => estimateMinutes(plannedSegments);

  double get estimatedCostUsd =>
      estimateCostUsd(_model.pricing, plannedSegments);

  /// Opens the native directory picker for the output destination; leaves the
  /// current directory unchanged when cancelled or when the picker fails.
  Future<void> pickOutputFolder() async {
    final String? path;
    try {
      path = await getDirectoryPath(initialDirectory: _outDir);
    } catch (_) {
      // Keep the current directory rather than crashing.
      return;
    }
    if (path == null) return;
    outDir = path;
  }
}
