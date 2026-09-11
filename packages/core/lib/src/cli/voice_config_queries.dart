import '../narration/cost.dart';
import '../narration/model_profiles.dart';
import 'voice_config.dart';

/// Pricing for [modelAlias], or [freePricing] when unconfigured.
AudioPricing pricingFor(VoiceConfig config, String modelAlias) =>
    config.pricing[modelAlias] ?? freePricing;

/// Resolves a `--voice` value to the provider voice id for [modelAlias].
(String id, String label) resolveVoice(
  VoiceConfig config,
  String modelAlias,
  String value,
) {
  final modelVoices = config.voices[modelAlias];
  if (modelVoices != null) {
    final voice = modelVoices[value];
    if (voice != null) return (voice.id, value);
  }
  return (value, value);
}

/// The gender tag for [voiceLabel] under [modelAlias], or null when untagged.
VoiceGender? genderFor(
  VoiceConfig config,
  String modelAlias,
  String voiceLabel,
) => config.voices[modelAlias]?[voiceLabel]?.gender;

/// The effective set of models: compiled fish bootstrap first, merged with [config].
List<TtsModelProfile> effectiveModels(VoiceConfig config) {
  final out = <TtsModelProfile>[];
  final bootstrap = kDefaultProfile.profile;
  final concrete = config.models;
  if (concrete.containsKey(bootstrap.alias)) {
    out.add(concrete[bootstrap.alias]!);
  } else {
    out.add(bootstrap);
  }
  for (final e in concrete.entries) {
    if (e.key == bootstrap.alias) continue;
    out.add(e.value);
  }
  return out;
}

/// Resolves `--model` value against effective set, or null if unknown.
TtsModelProfile? profileFor(String aliasOrId, VoiceConfig config) {
  for (final p in effectiveModels(config)) {
    if (p.alias == aliasOrId || p.id == aliasOrId) return p;
  }
  return null;
}

/// The model the CLI and GUI preselect on cold start.
TtsModelProfile defaultModelFor(VoiceConfig config) {
  final dm = config.defaultModel;
  if (dm != null && dm.trim().isNotEmpty) {
    final resolved = profileFor(dm.trim(), config);
    if (resolved != null) return resolved;
  }
  return kDefaultProfile.profile;
}

String? _resolveAlias(VoiceConfig config, String modelAlias, String value) {
  final modelVoices = config.voices[modelAlias];
  return modelVoices?[value]?.id ?? (value.isNotEmpty ? value : null);
}

/// The default voice (+ friendly label) for [model].
(String id, String label) defaultVoiceFor(
  TtsModelProfile model,
  VoiceConfig config,
) {
  final configured = config.defaults[model.alias];
  if (configured != null && configured.trim().isNotEmpty) {
    final id = _resolveAlias(config, model.alias, configured);
    if (id != null) return (id, configured);
    throw VoiceConfigurationError(
      'Default voice "$configured" for "${model.alias}" is not a configured '
      'voice or raw id.',
    );
  }
  if (model.alias == kDefaultProfile.profile.alias) {
    return (kDefaultProfile.voice, kDefaultProfile.voiceLabel);
  }
  throw VoiceConfigurationError(
    'No default voice configured for "${model.alias}". Set "defaults" in the '
    'voice config, or pass --voice / pick one in the app.',
  );
}

/// All selectable voices for [model] (or all models when null).
List<VoiceOption> voiceEntries({
  TtsModelProfile? model,
  required VoiceConfig config,
}) {
  final profiles = model != null ? [model] : effectiveModels(config);
  final entries = <VoiceOption>[];
  for (final p in profiles) {
    void add(String id, String label, bool isAlias) {
      if (entries.any((e) => e.model == p.alias && e.id == id)) return;
      entries.add(
        VoiceOption(
          model: p.alias,
          id: id,
          label: label,
          isAlias: isAlias,
          gender: genderFor(config, p.alias, label),
        ),
      );
    }

    for (final e
        in (config.voices[p.alias] ?? const <String, Voice>{}).entries) {
      add(e.value.id, e.key, true);
    }
    try {
      final (id, label) = defaultVoiceFor(p, config);
      add(id, label, false);
    } on VoiceConfigurationError {
      // No default for this model yet; skip (raw-id entry stays available).
    }
  }
  entries.sort((a, b) {
    final byModel = a.model.compareTo(b.model);
    if (byModel != 0) return byModel;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return entries;
}
