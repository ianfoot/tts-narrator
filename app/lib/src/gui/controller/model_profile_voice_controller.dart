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
/// There is no compiled default model: when the config directory has no models
/// (or no `default_model` that resolves to one), [profile] and [modelAlias] are
/// null and there is nothing to select or narrate with. Narration is blocked
/// until the user supplies a config (the first-run download prompt guides this).
///
/// The narration-settings side effects of the gender filter (rewriting the
/// narrator phrase in the passage prefix) live in [AppController], which owns
/// that setting and reacts to [voiceGenderFilter] writes through the facade.
class ModelProfileVoiceController extends ChangeNotifier {
  ModelProfileVoiceController({UserVoiceConfigLoader? loader})
    : _loader = loader ?? UserVoiceConfigLoader() {
    _voiceConfig = _loader.load();
    final def = defaultModelFor(_voiceConfig);
    _modelAlias = def?.alias;
    final voice = _defaultVoiceFor(def);
    _voice = voice?.$1 ?? '';
    _voiceLabel = voice?.$2;
  }

  final UserVoiceConfigLoader _loader;

  /// The preset default model (the resolved `default_model`), or null when the
  /// config has none; [changeModel] moves to other configured models.
  late String? _modelAlias;
  late VoiceConfig _voiceConfig;

  // --- Model & voice ------------------------------------------------

  /// The active model profile (alias resolved against the loaded config), or
  /// null when the config has no models / no resolvable default.
  TtsModelProfile? get profile {
    final alias = _modelAlias;
    return alias == null ? null : profileFor(alias, _voiceConfig);
  }

  VoiceConfig get voiceConfig => _voiceConfig;

  /// Warnings surfaced while loading the voice config (e.g. a skipped
  /// malformed model file). Rendered as a persistent, non-fatal banner.
  List<String> get configWarnings => _loader.warnings;

  String? get modelAlias => _modelAlias;

  /// Raw provider voice id; an empty string means "use the model default".
  String _voice = '';

  /// Friendly voice label when one was picked; null means the raw id.
  String? _voiceLabel;

  String get voice => _voice;

  String? get voiceLabel => _voiceLabel;

  /// Cost data for the active model (free until the config sets pricing, and
  /// always free when no model is configured).
  AudioPricing get pricing {
    final p = profile;
    return p == null ? freePricing : pricingFor(_voiceConfig, p.alias);
  }

  /// Resolves the provider settings block for [profile] (see
  /// `resolveSettings` in the core); used when assembling the run config.
  Map<String, String> resolveProviderSettings(TtsModelProfile profile) =>
      _loader.resolveProviderSettings(profile);

  /// The editable GUI options for the active model, declared by its model's
  /// plugin (the provider package). Empty when no model is configured or no
  /// plugin declares a spec — the app has no per-model UI knowledge.
  ModelUiSpec get modelUiSpec {
    final p = profile;
    return p == null
        ? const ModelUiSpec.empty()
        : ttsProviderRegistry.resolveOrNull(p.provider)?.modelUiSpecFor(p) ??
              const ModelUiSpec.empty();
  }

  /// Default voice for the active [profile] from the config, or null when the
  /// model has no default configured (or no model is active).
  (String, String)? get defaultVoice => _defaultVoiceFor(profile);

  /// Default voice for [model] from the config, or null when the model has no
  /// default configured.
  (String, String)? _defaultVoiceFor(TtsModelProfile? model) {
    if (model == null) return null;
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
  /// Returns false (leaving the selection unchanged) when no model is active.
  bool applyVoiceLabel(String label) {
    final p = profile;
    if (p == null) return false;
    final (id, _) = resolveVoice(_voiceConfig, p.alias, label);
    setVoice(id, label: label);
    return true;
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
  bool get hasGenderTags {
    final p = profile;
    return p != null &&
        (_voiceConfig.voices[p.alias]?.values.any((v) => v.gender != null) ??
            false);
  }

  /// Selectable voices for the active model, narrowed to [voiceGenderFilter].
  /// Each entry is `(value, displayLabel)`: tagged voices get a compact
  /// ` (m)`/` (f)`/` (n)` suffix so gender is visible in the dropdown.
  List<(String, String)> get voiceItems {
    final p = profile;
    return p == null
        ? const <(String, String)>[]
        : [
            for (final e in _genderFilteredVoiceEntries(p))
              (
                e.label,
                e.gender == null
                    ? e.label
                    : '${e.label} (${e.gender!.shorthand})',
              ),
          ];
  }

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
    final p = profile;
    if (p == null) return;
    final g = _voiceGender;
    if (g == VoiceGender.neutral) return;
    final matches = _genderFilteredVoiceEntries(p);
    if (matches.isEmpty) {
      _voiceGender = VoiceGender.neutral;
      return;
    }
    if (!matches.any((e) => e.id == _voice || e.label == _voiceLabel)) {
      // Prefer the model default when it matches the filter, else the first
      // matching voice — mirrors changeModel's reset-to-default semantics.
      late final VoiceOption pick;
      final def = _defaultVoiceFor(p);
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
