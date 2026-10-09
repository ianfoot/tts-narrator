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

/// Owns the narration settings and the editor's settings-panel visibility:
/// accent/style, passage prefix, per-segment sizing, the whole-file/sample/
/// out-dir/resume toggles, and the output folder persisted through
/// [SharedPreferences].
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
    for (final key in prefs?.getKeys() ?? const <String>{}) {
      if (!key.startsWith(_outputFormatPrefsPrefix)) continue;
      final saved = TtsAudioFormat.tryParse(prefs?.getString(key) ?? '');
      if (saved == null) continue;
      _outputFormats[key.substring(_outputFormatPrefsPrefix.length)] = saved;
    }
  }

  /// Preferences key holding the last output folder the user picked.
  static const _outDirPrefsKey = 'outDir';

  /// Preferences key holding the language tag the user last selected.
  static const _localePrefsKey = 'locale';

  /// Preferences key prefix holding each model's chosen output format.
  static const _outputFormatPrefsPrefix = 'outputFormat.';

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

  /// The default output folder path, always absolute, without creating it.
  ///
  /// [defaultOutDir] is the same path and creates it; this variant is for
  /// callers that only need to *show* the default (the editor status bar) and
  /// must not touch the filesystem on every build.
  static String defaultOutDirPath() =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      '$_defaultOutDirName';

  /// The default output folder, created on demand and always absolute.
  ///
  /// Absolute because GStreamer-backed playback on Linux resolves a relative
  /// path against a working directory a packaged app does not control. Under the
  /// system temp dir because the rendered audio is disposable.
  static String defaultOutDir() {
    final dir = Directory(defaultOutDirPath());
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// The persistent preference store; null when the host has none (tests).
  final SharedPreferences? _prefs;

  /// The OS-secure key store backing the API-key section of the run-setup panel;
  /// null when the host injects none (tests) — the key simply never falls back
  /// to secure storage.
  final ApiKeyStore? apiKeyStore;

  /// The open document (read for whole-file availability and the live plan).
  final DocumentController _document;

  /// The active model (read when assembling the run config and applying the
  /// narrator-gender passage-prefix rewrite for prompt-style models).
  final ModelProfileVoiceController _model;

  // --- Run setup panel -----------------------------------------------

  bool _runSetupPanelVisible = true;

  /// Whether the run-setup panel is shown on the editor. Driven by the toolbar
  /// toggle and, on macOS, the View menu command, so both dispatch through one
  /// piece of state.
  bool get runSetupPanelVisible => _runSetupPanelVisible;

  /// Flips [runSetupPanelVisible] and notifies listeners.
  void toggleRunSetupPanel() {
    _runSetupPanelVisible = !_runSetupPanelVisible;
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

  /// Voice-design prose, or null when the user has not edited the model's own
  /// [TtsModelProfile.defaultInstruct]. Held as an *override* so a model switch
  /// can go back to the new model's default: prose written for one model means
  /// nothing to the next.
  String? _instruct;

  /// The user's output-format choice per model alias, keyed rather than held as
  /// one value so switching models and coming back keeps each model's own
  /// choice. Read through [outputFormat], which clamps to what the active model
  /// declares.
  final Map<String, TtsAudioFormat> _outputFormats = {};

  /// Selected UI locale, or null to follow the platform's resolution. Only
  /// English is translated today, so the default is null; the preference is
  /// persisted now so adding a second `app_xx.arb` is a data change.
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

  /// Voice-design prose for a model that declares `"sends_instruct": true`: the
  /// user's edit when there is one, else the model's [TtsModelProfile
  /// .defaultInstruct], so a freshly selected voice-design model is runnable
  /// with no input. Empty for any other model.
  String get instruct => _instruct ?? _model.profile?.defaultInstruct ?? '';

  /// Records the prose exactly as typed, *including* the empty string.
  ///
  /// An empty value is a deliberate choice, not an absent one: collapsing it
  /// into "use the model's default" would make the field impossible to clear.
  /// [resetInstruct] is the only way back to the default.
  set instruct(String value) {
    if (value == _instruct) return;
    _instruct = value;
    notifyListeners();
  }

  /// Drops any user [instruct] override so the active model's own default shows
  /// again. Called on a model switch, where the previous override described a
  /// different model.
  ///
  /// Does not notify, for the same reason as [applyNarratorGender]: the model
  /// switch's own write owns the single broadcast.
  void resetInstruct() {
    _instruct = null;
  }

  /// Speech-rate multiplier (1.0 = normal), clamped to the run-setup panel's
  /// 0.25-2.0 slider range. Sent to providers via `NarrationConfig.speed`.
  double get speed => _speed;

  set speed(double value) {
    final clamped = value.clamp(0.25, 2.0);
    if (clamped == _speed) return;
    _speed = clamped;
    notifyListeners();
  }

  /// Minimum words per segment (clamped to the run-setup panel's 10-100
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
  /// segmenting it. When true, [minWords] is ignored and the run-setup panel
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
  /// (see `maxWholeFileLength` in the core). The run-setup panel hides the "Send
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

  /// The directory a run actually writes into: the chosen output folder, plus the
  /// open document's stem when it is backed by a file, so several documents can
  /// share one chosen folder. An in-memory document has no filename to name a
  /// folder after, so it writes straight into `outDir`. [buildConfig] resolves
  /// the same way; this getter exists so the UI can display it without
  /// assembling a config.
  String get resolvedOutDir => resolveOutputDir(
    outDir: _trimmedOutDir,
    inputPath: _document.documentPath,
    nestUnderInputName: _document.documentPath != null,
  );

  /// The chosen output folder, or the default when it is blank — the same
  /// fallback [buildConfig] applies, kept in one place so the status bar cannot
  /// disagree with where the run lands.
  String get _trimmedOutDir =>
      outDir.trim().isEmpty ? defaultOutDirPath() : outDir.trim();

  bool get resume => _resume;

  set resume(bool value) {
    if (value == _resume) return;
    _resume = value;
    notifyListeners();
  }

  /// The output formats the active model declares, in its own order.
  ///
  /// Empty when no model is selected, which is also what hides the control.
  List<TtsAudioFormat> get outputFormats => _model.profile?.formats ?? const [];

  /// Whether the run-setup panel should offer a format choice: only when the
  /// active model declares more than one, since a single option is not a choice.
  bool get outputFormatChoiceAvailable => outputFormats.length > 1;

  /// The format the next run writes, for the active model.
  ///
  /// The user's stored choice when the model still declares it, else the model's
  /// own first format. Clamping here rather than at write time means a model that
  /// dropped a format in an updated config file cannot be run in one it no
  /// longer serves.
  TtsAudioFormat get outputFormat {
    final profile = _model.profile;
    if (profile == null || profile.formats.isEmpty) {
      return TtsAudioFormat.mp3;
    }
    final stored = _outputFormats[profile.alias];
    if (stored != null && profile.supportsFormat(stored)) return stored;
    return profile.defaultFormat;
  }

  set outputFormat(TtsAudioFormat value) {
    final profile = _model.profile;
    if (profile == null || !profile.supportsFormat(value)) return;
    if (_outputFormats[profile.alias] == value) return;
    _outputFormats[profile.alias] = value;
    notifyListeners();
    _prefs?.setString(
      '$_outputFormatPrefsPrefix${profile.alias}',
      value.wireValue,
    );
  }

  /// Re-checks the whole-file cap on a document change: a document over
  /// `maxWholeFileLength` drops [sendWholeFile] instead of leaving the toggle
  /// "on" and planning a giant segment. The drop rides the facade's
  /// document-change broadcast, so this does not notify on its own.
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

  /// The environment `${ENV}` references in the provider block resolve against,
  /// shared with the loader so the status line and the run config can never
  /// disagree about what a value means.
  Map<String, String> get _environment => _model.environment;

  /// Whether a `${NAME}` secret reference in [value] resolves to a non-empty
  /// value. A ref the runtime cannot fulfil is not a usable key, so it must not
  /// be reported as coming from the environment.
  bool _envRefResolves(String value) {
    final name = envRefName(value);
    return name != null && (_environment[name]?.trim().isNotEmpty ?? false);
  }

  /// The resolved provider settings for [raw], with `api_key` stripped out.
  ///
  /// Expansion runs on everything *except* the credential, so the returned map
  /// never holds a secret (it would otherwise be serialised, logged, or shown in
  /// diagnostics) and an unfulfillable `api_key: "${VAR}"` degrades to "no key"
  /// rather than throwing out of `resolveSettings`.
  Map<String, String> _resolveProviderSettings(Map<String, String> raw) {
    final withoutKey = Map<String, String>.of(raw)..remove('api_key');
    return resolveSettings(withoutKey, env: _environment);
  }

  /// The key to send for [raw], or null when none is configured anywhere.
  ///
  /// The OS secure store outranks the config block and the environment: the
  /// provider file arrives from a remote download, so a key in it can be a
  /// pooled credential belonging to someone else, while a keychain entry was
  /// typed by this user deliberately.
  ///
  /// A null result is not an error — see `resolveProviderApiKey`.
  String? _resolveApiKey(Map<String, String> raw, TtsModelProfile p) {
    final stored = apiKeyStore?.value(p.provider);
    if (stored != null && stored.isNotEmpty) return stored;
    return resolveProviderApiKey(raw, env: _environment);
  }

  /// Where the active model's API key comes from, mirroring the precedence in
  /// [_resolveApiKey]. Drives the run-setup panel's status line.
  ///
  /// A `${ENV}` reference the runtime cannot fulfil does NOT count as "set via
  /// the environment" — it resolves to no key, so the status has to agree with
  /// what a run would actually send.
  ApiKeySource get apiKeySource {
    final p = _model.profile;
    if (p == null) return ApiKeySource.missing;
    final raw = _model.rawProviderSettings(p);
    final stored = apiKeyStore?.value(p.provider);
    if (stored != null && stored.isNotEmpty) return ApiKeySource.keychain;
    final value = raw['api_key']?.trim();
    if (value == null || value.isEmpty) return ApiKeySource.missing;
    if (isEnvReference(value)) {
      return _envRefResolves(value)
          ? ApiKeySource.environment
          : ApiKeySource.missing;
    }
    return ApiKeySource.config;
  }

  // --- Run config + live estimates ------------------------------------

  /// Assembles the run config for the current document + settings, narrating
  /// from the in-memory [DocumentController.text] (`sourceText`) so
  /// typed/pasted content needs no backing file. [inputPath] drives only
  /// output naming.
  ///
  /// A saved document gets a `nestOutputInInputSubdir` subdirectory under the
  /// chosen folder; an in-memory one writes into that folder directly (see
  /// [resolvedOutDir]).
  ///
  /// Throws a [FormatException] when the active model has no voice selected and
  /// no config default to fall back on.
  NarrationConfig buildConfig() {
    final p = _model.profile;
    if (p == null) {
      throw const NoModelConfigured();
    }
    // A voice-design model synthesizes its narrator from prose and sends no voice,
    // so it declares none; resolving one would demand a row the picker does not
    // show and block the run on a field dropped on the way out.
    String voiceId = '';
    String? label;
    if (p.sendsVoiceField) {
      final raw = _model.voice.trim();
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
    }
    final providerBlock = _model.rawProviderSettings(p);
    return NarrationConfig(
      inputPath: _document.documentPath ?? untitledDocumentName,
      sourceText: _document.text,
      profile: p,
      outputFormat: outputFormat,
      voice: voiceId,
      voiceLabel: label,
      language: _model.language,
      accent: accent,
      style: style,
      passagePrefix: passagePrefix,
      instruct: instruct,
      minWords: minWords,
      sendWholeFile: sendWholeFile,
      sampleLen: sampleLen,
      speed: speed,
      outDir: _trimmedOutDir,
      nestOutputInInputSubdir: _document.documentPath != null,
      resume: resume,
      providerSettings: _resolveProviderSettings(providerBlock),
      apiKey: _resolveApiKey(providerBlock, p),
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
