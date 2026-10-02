import '../narration/cost.dart';
import '../narration/model_profiles.dart';

/// The narrator gender a configured voice is tagged with.
enum VoiceGender {
  /// Male/narrator gender tag.
  male,

  /// Female/narrator gender tag.
  female,

  /// Neutral or unspecified gender tag.
  neutral;

  String get label => name;

  String get shorthand => switch (this) {
    VoiceGender.male => 'm',
    VoiceGender.female => 'f',
    VoiceGender.neutral => 'n',
  };
}

/// Parses the config-string form to a [VoiceGender], or null for anything
/// unrecognized (mislabels are dropped by the loader, not a hard error).
VoiceGender? parseVoiceGender(String? value) {
  if (value == null) return null;
  return switch (value.trim().toLowerCase()) {
    'male' => VoiceGender.male,
    'female' => VoiceGender.female,
    'neutral' => VoiceGender.neutral,
    _ => null,
  };
}

/// One configured voice in a model's `voices` block: the provider voice id
/// sent in the request body, plus optional metadata (gender, and room for more
/// fields later) — one entry per voice, so a voice's fields live together
/// instead of being split across parallel blocks.
class Voice {
  const Voice({required this.id, this.gender});

  /// Provider voice id sent in the request body.
  final String id;

  /// Optional narrator gender tag; null when untagged.
  final VoiceGender? gender;
}

/// A single selectable voice for the GUI voice picker and CLI listing.
class VoiceOption {
  const VoiceOption({
    required this.model,
    required this.id,
    required this.label,
    required this.isAlias,
    this.gender,
  });

  /// Model alias this voice belongs to (e.g. `gemini`, `fish`).
  final String model;

  /// Provider voice id sent in the request body.
  final String id;

  /// Human-readable label: the friendly alias when [isAlias], else the raw id.
  final String label;

  /// Whether [label] is a friendly alias from the config (vs a raw id).
  final bool isAlias;

  /// Optional narrator gender tag; null when untagged.
  final VoiceGender? gender;
}

/// One configured provider: the settings it is reached with, and the models
/// it serves.
///
/// A provider file owns the relationship to its models rather than each model
/// naming its provider, so a block is described once no matter how many models
/// sit behind it. [models] is ordered, and the first entry is the provider's
/// default model.
class ProviderConfig {
  const ProviderConfig({
    required this.name,
    this.settings = const {},
    this.models = const [],
  });

  /// Provider name — the `providers/<name>.json` stem, and the key a model
  /// profile's `provider` must match.
  final String name;

  /// Opaque settings block: `base_url`, `api_key`, ... The
  /// meaning of each key belongs to the provider, not to core.
  final Map<String, String> settings;

  /// Model aliases this provider serves, in order; first is the default.
  final List<String> models;
}

/// Voice data, model wiring, and per-provider settings, loaded from a config
/// *directory*.
///
/// Layout:
///   config.json                ordered provider registry — `providers`
///   providers/`name`.json      per-provider — `models` (aliases, in order) +
///                              `settings` (opaque string map)
///   models/`alias`.json        per-model — id, format, sample_rate,
///                              prompt_style, sends_voice, default_voice,
///                              pricing, voices (each entry: id + optional
///                              gender)
///
/// A provider lists the models it serves, and a model file does not name a
/// provider, so which block a model belongs to is stated in exactly one place.
/// Splitting into one file per provider and per model keeps the user's voice
/// library modular: edit a single model without touching the others, drop in a
/// new model, or copy a curated voice pack between machines.
///
/// `config.json` lists providers in order, and the first is the default
/// provider; the default model is the first model it lists. That ordering is
/// the config's, not the filesystem's, so it does not depend on which name
/// happens to sort first.
class VoiceConfig {
  const VoiceConfig({
    this.providers = const {},
    this.models = const {},
    this.defaults = const {},
    this.pricing = const {},
    this.voices = const {},
  });

  /// Configured providers, in `config.json` order (name → ProviderConfig).
  final Map<String, ProviderConfig> providers;

  /// The default provider: the first in [providers], or null when none are
  /// configured.
  ProviderConfig? get defaultProvider =>
      providers.isEmpty ? null : providers.values.first;

  /// Effective model profiles (alias → TtsModelProfile).
  final Map<String, TtsModelProfile> models;

  /// Per-model default voice labels (alias → label).
  final Map<String, String> defaults;

  /// Per-model pricing data.
  final Map<String, AudioPricing> pricing;

  /// Per-model configured voices (alias → label → Voice).
  final Map<String, Map<String, Voice>> voices;

  /// Pricing for [modelAlias], or free pricing when unconfigured.
  AudioPricing pricingFor(String modelAlias) =>
      pricing[modelAlias] ?? freePricing;

  /// Resolves a `--voice` value to the provider voice id for [modelAlias].
  (String id, String label) resolveVoice(String modelAlias, String value) {
    final modelVoices = voices[modelAlias];
    if (modelVoices != null) {
      final voice = modelVoices[value];
      if (voice != null) return (voice.id, value);
    }
    return (value, value);
  }

  /// The gender tag for [voiceLabel] under [modelAlias], or null when untagged.
  VoiceGender? genderFor(String modelAlias, String voiceLabel) =>
      voices[modelAlias]?[voiceLabel]?.gender;

  bool get isEmpty =>
      providers.isEmpty &&
      models.isEmpty &&
      defaults.isEmpty &&
      pricing.isEmpty &&
      voices.isEmpty;
}

class VoiceConfigurationError implements Exception {
  VoiceConfigurationError(this.message);
  final String message;

  @override
  String toString() => message;
}
