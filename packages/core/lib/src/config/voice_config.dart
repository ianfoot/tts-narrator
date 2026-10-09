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

/// One configured voice in a model's `voices` block: the provider voice id sent
/// in the request body, plus optional metadata for the picker.
///
/// The `voices` *key* is the voice id when the entry does not spell one out, so a
/// voice is always keyed by something unique: a name is not (Kokoro has three
/// `Santa`s), an id is.
class Voice {
  const Voice({required this.id, this.name, this.gender, this.language});

  /// Provider voice id sent in the request body.
  final String id;

  /// The name to show for this voice in the picker, or null to show the id.
  /// Cosmetic only. Two voices may share a name; they cannot share an id.
  final String? name;

  /// Optional narrator gender tag; null when untagged.
  final VoiceGender? gender;

  /// The language code this voice speaks, when the entry tags it explicitly.
  ///
  /// Null falls back to [languageFromVoiceId]. A UUID id like Fish Audio's
  /// carries no language prefix, so those voices must spell their language out
  /// here. An unknown code is ignored rather than mislabelled.
  final String? language;
}

/// The language of [voiceId], when its first character is one of [codes].
///
/// Multi-language models name their voices `<lang><gender>_<name>` (`bf_emma`,
/// `zf_xiaobei`), so the language is readable off the id. The prefix only
/// *proposes* a language: it counts when the model declares that code, so an
/// accidental letter match leaves the voice untagged rather than mislabelled.
///
/// Null for an empty or one-character id, or an undeclared prefix.
String? languageFromVoiceId(String voiceId, Iterable<String> codes) {
  if (voiceId.length < 2) return null;
  final prefix = voiceId.substring(0, 1);
  return codes.contains(prefix) ? prefix : null;
}

/// The narrator gender [voiceId] names, when its second character is one of
/// `m`/`f`/`n`.
///
/// The counterpart to [languageFromVoiceId]: the `<lang><gender>_<name>`
/// convention puts the gender second, so an entry needs no `gender` tag.
///
/// Only meaningful for language-prefixed ids; see [genderOfVoice].
VoiceGender? genderFromVoiceId(String voiceId) {
  if (voiceId.length < 2) return null;
  return switch (voiceId.substring(1, 2)) {
    'm' => VoiceGender.male,
    'f' => VoiceGender.female,
    'n' => VoiceGender.neutral,
    _ => null,
  };
}

/// A single selectable voice for the GUI voice picker and CLI listing.
class VoiceOption {
  const VoiceOption({
    required this.model,
    required this.id,
    required this.label,
    required this.isAlias,
    this.gender,
    this.language,
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

  /// Language code this voice speaks, read off the voice id; null when the
  /// model declares no languages or the id is not language-prefixed.
  final String? language;
}

/// One configured provider: the settings it is reached with, and the models
/// it serves.
///
/// A provider file owns the relationship to its models, so a block is described
/// once no matter how many models sit behind it. [models] is ordered; the first
/// is the default model.
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
///   models/`alias`.json        per-model — id, formats (mp3 and/or wav, first
///                              is the default), prompt_style, sends_voice,
///                              sends_language,
///                              default_voice, default_language, languages,
///                              pricing, voices (each keyed by its id, with an
///                              optional name and gender tag)
///
/// A provider lists the models it serves and a model file does not name a
/// provider, so membership is stated in exactly one place.
///
/// `config.json` orders providers; the first is the default provider, and the
/// default model is the first model it lists. Ordering comes from the config, not
/// the filesystem, so it does not depend on which name happens to sort first.
class VoiceConfig {
  const VoiceConfig({
    this.providers = const {},
    this.models = const {},
    this.defaults = const {},
    this.pricing = const {},
    this.voices = const {},
    this.languages = const {},
    this.defaultLanguages = const {},
  });

  /// Configured providers, in `config.json` order (name → ProviderConfig).
  final Map<String, ProviderConfig> providers;

  /// The default provider: the first in [providers], or null when none are
  /// configured.
  ProviderConfig? get defaultProvider =>
      providers.isEmpty ? null : providers.values.first;

  /// Effective model profiles (alias → TtsModelProfile).
  final Map<String, TtsModelProfile> models;

  /// Per-model default voices (alias → the voice's `voices` key or its name).
  final Map<String, String> defaults;

  /// Per-model pricing data.
  final Map<String, AudioPricing> pricing;

  /// Per-model configured voices (alias → voice id or name → Voice).
  final Map<String, Map<String, Voice>> voices;

  /// Per-model language tables (alias → code → label), in configured order. A model
  /// that declares languages supports picking a voice by language, so it only
  /// needs to list the codes it offers.
  final Map<String, Map<String, String>> languages;

  /// Per-model default language codes (alias → code), used when no voice is
  /// selected yet.
  final Map<String, String> defaultLanguages;

  /// The language table for [modelAlias] (code → label), empty when the model
  /// is single-language.
  Map<String, String> languagesFor(String modelAlias) =>
      languages[modelAlias] ?? const {};

  /// The default language code for [modelAlias], or null when unconfigured.
  String? defaultLanguageFor(String modelAlias) => defaultLanguages[modelAlias];

  /// The language [voiceId] speaks under [modelAlias], or null when the model
  /// declares no languages.
  ///
  /// The entry's own `language` tag wins — the only way to name a language for a
  /// voice whose id is not language-prefixed, like a UUID. Otherwise the id prefix
  /// is read (see [languageFromVoiceId]). Either way the result must be a
  /// declared code, so an unrecognised tag is null.
  String? languageFor(String modelAlias, Voice voice) {
    final codes = languagesFor(modelAlias);
    if (codes.isEmpty) return null;
    final tagged = voice.language;
    if (tagged != null && codes.containsKey(tagged)) return tagged;
    return languageFromVoiceId(voice.id, codes.keys);
  }

  /// The language [voiceId] speaks under [modelAlias], looked up from its
  /// configured entry when one exists, else read off the id prefix.
  ///
  /// Takes a raw id so a typed-in id with no entry behind it still narrows the
  /// picker via the id-prefix path.
  String? languageForId(String modelAlias, String voiceId) =>
      languageFor(modelAlias, voiceFor(modelAlias, voiceId) ?? Voice(id: voiceId));

  /// Pricing for [modelAlias], or free pricing when unconfigured.
  AudioPricing pricingFor(String modelAlias) =>
      pricing[modelAlias] ?? freePricing;

  /// The configured [value] under [modelAlias] — the `voices` key, or failing
  /// that the entry naming it in `name` — or null when neither matches.
  ///
  /// Both lookups exist because a config may key a voice by its id (Kokoro) or
  /// by its name (Fish), and a user may type either.
  Voice? voiceFor(String modelAlias, String value) {
    final modelVoices = voices[modelAlias];
    if (modelVoices == null) return null;
    final byKey = modelVoices[value];
    if (byKey != null) return byKey;
    for (final voice in modelVoices.values) {
      if (voice.name == value) return voice;
    }
    // A third match, by id: Fish voices are keyed by name and carry UUID ids, so
    // a pasted id still finds the entry — and with it, its language tag.
    for (final voice in modelVoices.values) {
      if (voice.id == value) return voice;
    }
    return null;
  }

  /// Resolves a `--voice` value to the provider voice id for [modelAlias].
  ///
  /// The label is what the picker shows: the voice's `name` when it has one, so a
  /// name comes back as its name rather than its id.
  (String id, String label) resolveVoice(String modelAlias, String value) {
    final voice = voiceFor(modelAlias, value);
    return voice == null ? (value, value) : (voice.id, voice.name ?? value);
  }

  /// The gender for [voice] under [modelAlias], or null when unknown.
  ///
  /// A configured entry's own `gender` tag wins. An untagged voice falls back to
  /// the second character of its id, but only for a model that declares
  /// languages — that declaration is what makes its ids `<lang><gender>_<name>`.
  /// Without it a bare id like `nala` would read as neutral.
  ///
  /// Takes the entry rather than a name: [voiceFor]'s name scan returns the first
  /// of several voices sharing a name, so asking about the second Santa would
  /// answer for the first.
  VoiceGender? genderOfVoice(String modelAlias, Voice voice) {
    final tagged = voice.gender;
    if (tagged != null) return tagged;
    if (languagesFor(modelAlias).isEmpty) return null;
    return genderFromVoiceId(voice.id);
  }

  /// The gender for [voiceLabel] under [modelAlias], or null when unknown.
  ///
  /// [voiceLabel] may be a configured name or a raw id; one with no entry is read
  /// as a bare id. Prefer [genderOfVoice] when the caller already holds the voice.
  VoiceGender? genderFor(String modelAlias, String voiceLabel) => genderOfVoice(
    modelAlias,
    voiceFor(modelAlias, voiceLabel) ?? Voice(id: voiceLabel),
  );

  bool get isEmpty =>
      providers.isEmpty &&
      models.isEmpty &&
      defaults.isEmpty &&
      pricing.isEmpty &&
      voices.isEmpty &&
      languages.isEmpty &&
      defaultLanguages.isEmpty;
}

class VoiceConfigurationError implements Exception {
  VoiceConfigurationError(this.message);
  final String message;

  @override
  String toString() => message;
}
