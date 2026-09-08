import 'package:flutter/foundation.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'config_loader.dart';

/// Owns the active model profile, voice selection, and narrator-gender filter
/// for the TTS Narrator GUI.
///
/// The controller loads the shared [VoiceConfig] (same directory the CLI reads,
/// via its [UserVoiceConfigLoader]) and exposes the resolved profile, the selected
/// voice, and the gender-filtered voice items. [AppController] forwards its
/// model & voice surface here and re-broadcasts notifications, so callers keep
/// a single change stream.
///
/// The narration-settings side effects of the gender filter (rewriting the
/// narrator phrase in the passage prefix) live in [AppController], which owns
/// that setting and reacts to [voiceGenderFilter] writes through the facade.
class ModelProfileVoiceController extends ChangeNotifier {
  ModelProfileVoiceController({UserVoiceConfigLoader? loader})
    : _loader = loader ?? UserVoiceConfigLoader() {
    _voiceConfig = _loader.load();
    _modelAlias = defaultModelFor(_voiceConfig).alias;
    final def = _defaultVoiceFor(profile);
    _voice = def?.$1 ?? kDefaultProfile.voice;
    _voiceLabel = def?.$2;
  }

  final UserVoiceConfigLoader _loader;

  /// The preset default model (fish's compiled bootstrap unless `default_model`
  /// in the config names another); [changeModel] moves to other configured
  /// models.
  late String _modelAlias;
  late VoiceConfig _voiceConfig;

  // --- Model & voice ------------------------------------------------

  /// The active model profile (alias resolved against the loaded config).
  TtsModelProfile get profile =>
      profileFor(_modelAlias, _voiceConfig) ?? kDefaultProfile.profile;

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

  /// Cost data for the active model (free until the config sets pricing).
  AudioPricing get pricing => _voiceConfig.pricingFor(profile.alias);

  /// Resolves the provider settings block for [profile] (see
  /// `resolveSettings` in the core); used when assembling the run config.
  Map<String, String> resolveProviderSettings(TtsModelProfile profile) =>
      _loader.resolveProviderSettings(profile);

  /// The editable GUI options for the active model, declared by its model's
  /// plugin (the provider package). Empty when no plugin declares a spec — the
  /// app has no per-model UI knowledge.
  ModelUiSpec get modelUiSpec =>
      ttsProviderRegistry
          .resolveOrNull(profile.provider)
          ?.modelUiSpecFor(profile) ??
      const ModelUiSpec.empty();

  /// Default voice for the active [profile] from the config, or the compiled
  /// fish bootstrap for fish; null when the model has no default configured.
  (String, String)? get defaultVoice => _defaultVoiceFor(profile);

  /// Default voice for [model] from the config, or the compiled fish bootstrap
  /// for fish; null when the model has no default configured.
  (String, String)? _defaultVoiceFor(TtsModelProfile model) {
    try {
      return defaultVoiceFor(model, _voiceConfig);
    } on VoiceConfigurationError {
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
    // Gender tags are per-model; the filter does not carry across a switch.
    _voiceGender = VoiceGender.neutral;
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

  // --- Voice gender -------------------------------------------------

  /// Narrator-gender selection. Two uses, both flowing through this one field:
  /// narrowing the voice picker for models whose config tags voices with a
  /// gender, and (via the openrouter plugin's `gender` model option) driving
  /// the narrator phrase in the passage prefix for prompt-style models. The
  /// passage-prefix side effect is applied by [AppController], which owns that
  /// setting. [VoiceGender.neutral] is "any / unselected".
  VoiceGender _voiceGender = VoiceGender.neutral;

  /// The active narrator gender; [VoiceGender.neutral] is "any".
  VoiceGender get voiceGenderFilter => _voiceGender;

  set voiceGenderFilter(VoiceGender value) {
    if (value == _voiceGender) return;
    _voiceGender = value;
    _applyGenderFilter();
    notifyListeners();
  }

  /// Whether the active model tags any of its voices with a gender (drives the
  /// voice-picker gender control in "Model & voice").
  bool get hasGenderTags =>
      _voiceConfig.voices[profile.alias]?.values.any((v) => v.gender != null) ??
      false;

  /// Selectable voices for the active model, narrowed to [voiceGenderFilter].
  /// Each entry is `(value, displayLabel)`: tagged voices get a compact
  /// ` (m)`/` (f)`/` (n)` suffix so gender is visible in the dropdown.
  List<(String, String)> get voiceItems => [
    for (final e in _genderFilteredVoiceEntries(profile))
      (
        e.label,
        e.gender == null ? e.label : '${e.label} (${e.gender!.shorthand})',
      ),
  ];

  List<VoiceOption> _genderFilteredVoiceEntries(TtsModelProfile p) {
    final all = voiceEntries(model: p, config: _voiceConfig);
    if (_voiceGender == VoiceGender.neutral) return all;
    // Untagged models have nothing to filter against: a gender set via a
    // prompt-style model's option still keeps the full voice list.
    final tagged =
        _voiceConfig.voices[p.alias]?.values.any((v) => v.gender != null) ??
        false;
    if (!tagged) return all;
    return [
      for (final e in all)
        if (e.gender == _voiceGender) e,
    ];
  }

  /// Adjusts the selected voice to match the active [voiceGenderFilter]: when
  /// the model's voices are gender-tagged, auto-switches the selection so it
  /// matches the filter. Selecting "any" ([VoiceGender.neutral]) leaves the
  /// voice untouched. When a gender is picked but the model has no voices of
  /// that gender, the filter reverts to "any" so the picker keeps the full
  /// list rather than leaving a voice hidden behind an empty filter.
  void _applyGenderFilter() {
    final g = _voiceGender;
    if (g == VoiceGender.neutral) return;
    final matches = _genderFilteredVoiceEntries(profile);
    if (matches.isEmpty) {
      _voiceGender = VoiceGender.neutral;
      return;
    }
    if (!matches.any((e) => e.id == _voice || e.label == _voiceLabel)) {
      // Prefer the model default when it matches the filter, else the first
      // matching voice — mirrors changeModel's reset-to-default semantics.
      late final VoiceOption pick;
      final def = _defaultVoiceFor(profile);
      if (def != null) {
        final defEntry = matches.where((e) => e.id == def.$1);
        pick = defEntry.isNotEmpty ? defEntry.first : matches.first;
      } else {
        pick = matches.first;
      }
      _voice = pick.id;
      _voiceLabel = pick.label;
    }
  }
}
