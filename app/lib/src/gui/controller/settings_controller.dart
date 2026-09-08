import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'document_controller.dart';
import 'model_profile_voice_controller.dart';
import '../theme/app_text_tokens.dart' show TextTokens, fillTextTemplate;

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
  }) : _prefs = prefs {
    final savedOutDir = prefs?.getString(_outDirPrefsKey);
    if (savedOutDir != null && savedOutDir.trim().isNotEmpty) {
      _outDir = savedOutDir;
    }
  }

  /// Preferences key holding the last output folder the user picked.
  static const _outDirPrefsKey = 'outDir';

  /// The persistent preference store; null when the host has none (tests).
  final SharedPreferences? _prefs;

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

  String _accent = TextTokens.defaults_accent;
  bool _useCalmTag = false;
  int _minWords = TextTokens.defaults_minWords;
  bool _sendWholeFile = false;
  int? _sampleLen;
  String _outDir = TextTokens.defaults_outDir;
  bool _resume = false;
  String _style = TextTokens.defaults_style;
  String _passagePrefix = TextTokens.defaults_passagePrefix;

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

  static const _genderFemalePhrase =
      TextTokens.gui_controller_genderPhrases_female;
  static const _genderMalePhrase = TextTokens.gui_controller_genderPhrases_male;

  /// Whether [prefix] contains the exact male-phrase form. `female narrator`
  /// already contains `male narrator` as a substring, so a plain
  /// [String.contains] can't tell them apart; a phrase is "male" only when the
  /// female form isn't also present.
  static bool _hasMaleNarratorPhrase(String prefix) =>
      prefix.contains(_genderMalePhrase) &&
      !prefix.contains(_genderFemalePhrase);

  /// Applies the narrator phrase in [_passagePrefix] to match [gender] on a
  /// prompt-style model: `female narrator` ↔ `male narrator` when switching
  /// between the two, or back to the ungendered default when clearing to
  /// "any" (null). Only the exact phrases are swapped — custom prefixes are
  /// left alone. The facade's gender-filter write owns the single
  /// notification, so this mutates without notifying.
  void applyNarratorGender(VoiceGender? gender) {
    if (!_model.profile.promptStyle) return;
    if (gender == VoiceGender.male &&
        _passagePrefix.contains(_genderFemalePhrase)) {
      _passagePrefix = _passagePrefix.replaceAll(
        _genderFemalePhrase,
        _genderMalePhrase,
      );
    } else if (gender == VoiceGender.female &&
        _hasMaleNarratorPhrase(_passagePrefix)) {
      _passagePrefix = _passagePrefix.replaceAll(
        _genderMalePhrase,
        _genderFemalePhrase,
      );
    } else if (gender == null && _hasMaleNarratorPhrase(_passagePrefix)) {
      _passagePrefix = _passagePrefix.replaceAll(
        _genderMalePhrase,
        _genderFemalePhrase,
      );
    }
  }

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
    final raw = _model.voice.trim();
    String voiceId;
    String? label;
    if (raw.isEmpty) {
      final def = _model.defaultVoice;
      if (def == null) {
        throw FormatException(
          fillTextTemplate(TextTokens.gui_controller_errors_noVoiceSelected, {
            'modelAlias': p.alias,
          }),
        );
      }
      voiceId = def.$1;
      label = def.$2 == def.$1 ? null : def.$2;
    } else {
      final (id, resolvedLabel) = _model.voiceConfig.resolveVoice(p.alias, raw);
      voiceId = id;
      label = (_model.voiceLabel != null && id == raw)
          ? _model.voiceLabel
          : (resolvedLabel != id ? resolvedLabel : null);
    }
    return NarrationConfig(
      inputPath: _document.documentPath ?? TextTokens.app_untitledDocument,
      sourceText: _document.text,
      profile: p,
      voice: voiceId,
      voiceLabel: label,
      accent: accent,
      style: style,
      useCalmTag: useCalmTag,
      passagePrefix: passagePrefix,
      minWords: minWords,
      sendWholeFile: sendWholeFile,
      sampleLen: sampleLen,
      outDir: outDir.trim().isEmpty
          ? TextTokens.defaults_outDir
          : outDir.trim(),
      resume: resume,
      providerSettings: _model.resolveProviderSettings(p),
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

  double get estimatedCostUsd => estimateCostUsd(_model.pricing, plannedSegments);

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