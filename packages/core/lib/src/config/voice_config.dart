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
/// sent in the request body, plus optional metadata (the name shown in the
/// picker, the narrator gender, and room for more fields later) — one entry per
/// voice, so a voice's fields live together instead of being split across
/// parallel blocks.
///
/// The `voices` *key* is the voice id whenever the entry does not spell one out,
/// which is what lets a voice be keyed by something that is always unique: a
/// name is not (Kokoro has three `Santa`s), an id is.
class Voice {
  const Voice({required this.id, this.name, this.gender, this.language});

  /// Provider voice id sent in the request body.
  final String id;

  /// The name to show for this voice in the picker, or null to show the id.
  ///
  /// Purely cosmetic — the id is what gets sent, and what the config keys on.
  /// Two voices may share a name; they cannot share an id.
  final String? name;

  /// Optional narrator gender tag; null when untagged.
  final VoiceGender? gender;

  /// The language code this voice speaks, when the entry tags it explicitly.
  ///
  /// Null to fall back to [languageFromVoiceId], which reads the code off the id
  /// itself — the `<lang><gender>_<name>` convention Kokoro uses. A UUID like
  /// Fish Audio's carries no such prefix, so those voices must spell their
  /// language out here. The tag is only honoured when it names a code the model
  /// declares; an unknown code is ignored rather than mislabelled.
  final String? language;
}

/// The language of [voiceId], when its first character is one of [codes].
///
/// Multi-language models name their voices `<lang><gender>_<name>` (`bf_emma`,
/// `jf_alpha`, `zf_xiaobei`), so the language is readable off the id instead of
/// being repeated on every voice entry. The id prefix only *proposes* a
/// language: it counts when the model actually declares that code, so a model
/// whose voices happen to start with a letter it does not offer a language for
/// is left untagged rather than mislabelled.
///
/// Returns null for an empty id, a one-character id (no name after the
/// prefix), or a prefix the model does not declare.
String? languageFromVoiceId(String voiceId, Iterable<String> codes) {
  if (voiceId.length < 2) return null;
  final prefix = voiceId.substring(0, 1);
  return codes.contains(prefix) ? prefix : null;
}

/// The narrator gender [voiceId] names, when its second character is one of
/// `m`/`f`/`n`.
///
/// The counterpart to [languageFromVoiceId]: the same `<lang><gender>_<name>`
/// convention that puts the language first puts the gender second, so a voice
/// entry needs no `gender` tag of its own — the id already says it.
///
/// Only meaningful for ids that *are* language-prefixed; see [languageFor].
/// Returns null for an empty or one-character id, or an unrecognised letter.
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
///   models/`alias`.json        per-model — id, formats (mp3 and/or wav, first
///                              is the default), prompt_style, sends_voice,
///                              sends_language,
///                              default_voice, default_language, languages,
///                              pricing, voices (each keyed by its id, with an
///                              optional name and gender tag)
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

  /// Per-model language tables (alias → code → label), in configured order.
  ///
  /// A model that declares languages supports picking a voice by language, and
  /// each voice's own language is read off its id — so a model only lists the
  /// codes it offers here.
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
  /// The voice entry's own `language` tag wins — that is the only way to name a
  /// language for a voice whose id is not language-prefixed, like a UUID. When
  /// the entry tags nothing, the id prefix is read instead (see
  /// [languageFromVoiceId]), which is what makes Kokoro's `bf_emma` British
  /// without repeating `b` on every entry. Either way the result is checked
  /// against the model's declared codes, so an unrecognised tag is null.
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
  /// Takes a raw id rather than a [Voice] because the caller may hold a
  /// free-form id with no entry behind it — the id-prefix path stays available
  /// then, so a typed-in id can still narrow the picker.
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
    // A third match, by id: Fish voices are keyed by name and carry UUID ids,
    // so a user who pastes an id (or the picker hands one over) still finds the
    // entry behind it — and with it, its explicit language tag.
    for (final voice in modelVoices.values) {
      if (voice.id == value) return voice;
    }
    return null;
  }

  /// Resolves a `--voice` value to the provider voice id for [modelAlias].
  ///
  /// The returned label is what the picker shows for that voice — its `name`
  /// when it has one — so a name always comes back as its name, never as its id.
  (String id, String label) resolveVoice(String modelAlias, String value) {
    final voice = voiceFor(modelAlias, value);
    return voice == null ? (value, value) : (voice.id, voice.name ?? value);
  }

  /// The gender for [voice] under [modelAlias], or null when unknown.
  ///
  /// A configured entry's own `gender` tag wins. An untagged voice falls back to
  /// the second character of its id — but only for a model that declares
  /// languages, because that declaration is what makes its ids
  /// `<lang><gender>_<name>` and their second character a gender. Without that
  /// evidence a bare id like `nala` would be misread as a neutral voice.
  ///
  /// Takes the entry itself rather than a name to look up: [genderFor] has to go
  /// through [voiceFor], whose name scan returns the *first* of several voices
  /// sharing a name, so asking it about the second Santa would answer for the
  /// first.
  VoiceGender? genderOfVoice(String modelAlias, Voice voice) {
    final tagged = voice.gender;
    if (tagged != null) return tagged;
    if (languagesFor(modelAlias).isEmpty) return null;
    return genderFromVoiceId(voice.id);
  }

  /// The gender for [voiceLabel] under [modelAlias], or null when unknown.
  ///
  /// [voiceLabel] may be a configured name or a raw id; a value with no config
  /// entry is read as a bare id. Prefer [genderOfVoice] when the caller already
  /// holds the voice — see its note on duplicate names.
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
