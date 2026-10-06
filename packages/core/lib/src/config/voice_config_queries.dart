import '../narration/cost.dart';
import '../narration/model_profiles.dart';
import 'voice_config.dart';

/// Pricing for [modelAlias], or [freePricing] when unconfigured.
AudioPricing pricingFor(VoiceConfig config, String modelAlias) =>
    config.pricing[modelAlias] ?? freePricing;

/// Resolves a `--voice` value to the provider voice id for [modelAlias].
///
/// The value may be a `voices` key or a voice's `name`; the label comes back as
/// the voice's name when it has one.
(String id, String label) resolveVoice(
  VoiceConfig config,
  String modelAlias,
  String value,
) => config.resolveVoice(modelAlias, value);

/// The gender for [voiceLabel] under [modelAlias]: its entry's `gender` tag when
/// it has one, else the one its id names (for language-prefixed id schemes).
/// Null when neither applies.
VoiceGender? genderFor(
  VoiceConfig config,
  String modelAlias,
  String voiceLabel,
) => config.genderFor(modelAlias, voiceLabel);

/// The language code [voiceId] speaks under [modelAlias], or null when the
  /// model declares no languages or neither its entry nor its id prefix names a
  /// declared code.
  String? languageFor(VoiceConfig config, String modelAlias, String voiceId) =>
      config.languageForId(modelAlias, voiceId);

/// The configured models, sorted by alias. Models exist only in the config —
/// there is no compiled fallback — so an empty config yields no models.
List<TtsModelProfile> effectiveModels(VoiceConfig config) {
  final aliases = config.models.keys.toList()..sort();
  return [for (final alias in aliases) config.models[alias]!];
}

/// Resolves a model by alias or id against the configured models, or null when
/// unknown.
TtsModelProfile? profileFor(String aliasOrId, VoiceConfig config) {
  for (final p in effectiveModels(config)) {
    if (p.alias == aliasOrId || p.id == aliasOrId) return p;
  }
  return null;
}

/// The model the CLI and GUI preselect: the first model of the first
/// configured provider, or null when there is none.
///
/// No compiled default exists. The default is whatever the config lists
/// first -- `config.json` orders the providers, and a provider file orders its
/// models -- so a user changes it by reordering, not by editing a key. An
/// unresolvable first entry (a model file that failed to load, say) yields
/// null rather than silently falling through to the next one, because "the
/// config says this is first" is not a licence to substitute something else.
TtsModelProfile? defaultModelFor(VoiceConfig config) {
  final provider = config.defaultProvider;
  if (provider == null || provider.models.isEmpty) return null;
  return profileFor(provider.models.first, config);
}

String? _resolveAlias(VoiceConfig config, String modelAlias, String value) =>
    config.voiceFor(modelAlias, value)?.id ?? (value.isNotEmpty ? value : null);

/// The name to show for [value] — its own, when it names a configured voice.
String _labelFor(VoiceConfig config, String modelAlias, String value) =>
    config.voiceFor(modelAlias, value)?.name ?? value;

/// The default voice (+ friendly label) for [model].
///
/// Only a configured `defaults` entry (or the voice named by it) can be the
/// default: models do not bundle a compiled default voice.
(String id, String label) defaultVoiceFor(
  TtsModelProfile model,
  VoiceConfig config,
) {
  final configured = config.defaults[model.alias];
  if (configured != null && configured.trim().isNotEmpty) {
    final id = _resolveAlias(config, model.alias, configured);
    if (id != null) return (id, _labelFor(config, model.alias, configured));
    throw VoiceConfigurationError(
      'Default voice "$configured" for "${model.alias}" is not a configured '
      'voice or raw id.',
    );
  }
  throw VoiceConfigurationError(
    'No default voice configured for "${model.alias}". Set "defaults" in the '
    'voice config, or pass --voice / pick one in the app.',
  );
}

/// All selectable voices for [model] (or all models when null), narrowed to
/// [language] when given.
///
/// A voice whose id is not language-prefixed is kept whatever [language] is
/// asked for: an untagged voice has no language to be in the wrong one, and
/// hiding it would make a free-form voice unreachable once a language is picked.
List<VoiceOption> voiceEntries({
  TtsModelProfile? model,
  required VoiceConfig config,
  String? language,
}) {
  final profiles = model != null ? [model] : effectiveModels(config);
  final entries = <VoiceOption>[];
  for (final p in profiles) {
    // The voice itself is passed down rather than its label: the gender has to
    // come off this entry, not off a name lookup, since several voices in one
    // model may share a name (Kokoro has three Santas) and a name lookup would
    // answer for the first of them.
    void add(Voice voice, String label, bool isAlias) {
      final id = voice.id;
      if (entries.any((e) => e.model == p.alias && e.id == id)) return;
      // Pass the voice itself, not its id: Fish voices are keyed by name and
      // carry UUID ids, so `voiceFor` cannot look one up to read its tag, and
      // the tag is the only way to know its language.
      final voiceLanguage = config.languageFor(p.alias, voice);
      if (language != null &&
          voiceLanguage != null &&
          voiceLanguage != language) {
        return;
      }
      entries.add(
        VoiceOption(
          model: p.alias,
          id: id,
          label: label,
          isAlias: isAlias,
          gender: config.genderOfVoice(p.alias, voice),
          language: voiceLanguage,
        ),
      );
    }

    for (final e
        in (config.voices[p.alias] ?? const <String, Voice>{}).entries) {
      // A voice shows its name when it has one, else its `voices` key.
      add(e.value, e.value.name ?? e.key, true);
    }
    try {
      final (id, label) = defaultVoiceFor(p, config);
      add(config.voiceFor(p.alias, id) ?? Voice(id: id), label, false);
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
