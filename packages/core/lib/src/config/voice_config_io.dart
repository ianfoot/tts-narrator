import 'dart:convert';
import 'dart:io';

import '../narration/audio_format.dart';
import '../narration/cost.dart';
import '../narration/model_profiles.dart';
import 'voice_config.dart';

/// File name of the config directory marker, in the config directory root.
///
/// The marker holds no configuration: every file in the directory is found by
/// walking it, so adding a model or a provider is a matter of dropping in a
/// file and editing nothing. It exists so a directory can be recognised as a
/// voice config at all — an empty `providers/` is otherwise indistinguishable
/// from one that was never populated.
const String kVoiceConfigRegistryName = 'config.json';

/// Subdirectory of the config directory holding one `<name>.json` per provider.
const String kVoiceConfigProvidersDir = 'providers';

/// Subdirectory of the config directory holding one `<alias>.json` per model.
///
/// A model file directly inside is served on every platform; one inside a
/// platform subdirectory ([kVoiceConfigModelsDir]/`macos`/`<alias>.json`) is
/// served only there, which is how a backend that exists on one platform does
/// not have to be listed per platform everywhere.
const String kVoiceConfigModelsDir = 'models';

/// Subdirectory of the config directory holding the *user's* config layer.
///
/// `config.json`, `providers/` and `models/` hold the shipped baseline, which
/// the app downloads and never rewrites. `user/` holds the same layout one level
/// down and belongs to the user: [loadVoiceConfig] reads it as a second layer and
/// [VoiceConfigStore] writes only there, so each file there shadows its
/// counterpart in the baseline.
const String kVoiceConfigOverlayDirName = 'user';

/// Platform tags a voice config may be keyed by.
///
/// Single source of truth for the tag strings, which name subdirectories under
/// `models/`. They live here rather than beside any one caller because the
/// loader has to know them to decide which subdirectories to read and which to
/// report as typos.
const String kPlatformTagMacos = 'macos';
const String kPlatformTagLinux = 'linux';
const String kPlatformTagWindows = 'windows';

/// Every tag [kPlatformTagMacos], [kPlatformTagLinux] and [kPlatformTagWindows]
/// name, for validating a config that keys models by platform.
///
/// A key outside this set is rejected rather than ignored: a misspelled tag would
/// claim nothing on the platform it was meant for, and naming it beats silently
/// serving an empty list.
const Set<String> kVoiceConfigPlatformTags = {
  kPlatformTagMacos,
  kPlatformTagLinux,
  kPlatformTagWindows,
};

/// Loads a [VoiceConfig] from a config *directory* ([configDir]).
///
/// Reads the three file kinds described on [kVoiceConfigOverlayDirName]'s
/// sibling layout — marker, provider files, model files — with the user's overlay
/// loaded on top and each file it holds replacing its counterpart, so the
/// baseline stays untouched and re-downloadable. Everything is merged before the
/// result is built, so a [VoiceConfig] cannot tell which layer a part came from
/// — except in warning text, where an overlay problem is prefixed so it can be
/// traced.
///
/// Membership lives in the model file, not the provider: each model names the
/// `provider` that serves it, so adding a model never means editing a provider.
/// Provider files carry settings only.
///
/// Providers are ordered by what they are rather than by a declared order: the
/// first that carries an `api_key` is the default provider — cloud before local —
/// and the rest follow alphabetically. The default model is the default
/// provider's first model alphabetically.
///
/// A model file naming a provider with no file for it is reported as a warning
/// and left out, since without settings there is nowhere to send a request. A
/// model file that parses keeps every usable part of itself, so one bad voice
/// entry costs only itself.
///
/// If the config directory is missing, this returns an empty config. Fetching
/// defaults is the caller's decision: await `downloadVoiceConfigFiles()`
/// explicitly first if you want them.
///
/// [platformTag] selects which model files are in play: those directly in
/// `models/`, plus those in `models/`[platformTag] if it names a platform. A
/// subdirectory under `models/` that is not a platform tag is reported and its
/// contents ignored, so a typo does not read as an empty platform. Omit the tag
/// to read every platform's models, for a caller inspecting the config as data
/// rather than as this machine's configuration.
///
/// Returns the loaded config plus warnings for anything skipped or broken.
(VoiceConfig, List<String>) loadVoiceConfig(
  String configDir, {
  String? platformTag,
}) {
  // Download is not triggered here so this stays synchronous disk I/O; callers
  // wanting remote defaults await downloadVoiceConfigFiles() first.
  if (!Directory(configDir).existsSync()) {
    return (const VoiceConfig(), <String>[]);
  }
  final overlayDir =
      '$configDir${Platform.pathSeparator}$kVoiceConfigOverlayDirName';

  final base = _loadProviderLayer(configDir);
  final overlay = _loadProviderLayer(overlayDir);

  final baseModels = _loadModelLayer(configDir, platformTag);
  final overlayModels = _loadModelLayer(overlayDir, platformTag);

  final warnings = <String>[
    ...base.warnings,
    ...overlay.warnings.map((w) => 'Overlay: $w'),
    ...baseModels.warnings,
    ...overlayModels.warnings.map((w) => 'Overlay: $w'),
  ];

  // The overlay shadows file for file, so its providers lead: that is how a user
  // overrides one without having to say so.
  final names = <String>[
    ...overlay.order.where((n) => base.providers.containsKey(n)),
    ...base.order,
  ];

  final providers = <String, ProviderConfig>{};

  final models = <String, TtsModelProfile>{};
  final defaults = <String, String>{};
  final pricing = <String, AudioPricing>{};
  final voices = <String, Map<String, Voice>>{};
  final languages = <String, Map<String, String>>{};
  final defaultLanguages = <String, String>{};

  // A model the overlay has, wins over the baseline's — merged alias by alias,
  // since a model file is the unit of configuration.
  final servedBy = <String, List<String>>{};
  for (final entry in <String, _ParsedModel>{
    ...baseModels.models,
    ...overlayModels.models,
  }.entries) {
    final m = entry.value;
    models[entry.key] = m.profile;
    if (m.defaultVoice != null) defaults[entry.key] = m.defaultVoice!;
    if (m.pricing != null) pricing[entry.key] = m.pricing!;
    if (m.voices.isNotEmpty) voices[entry.key] = m.voices;
    if (m.languages.isNotEmpty) languages[entry.key] = m.languages;
    if (m.defaultLanguage != null) {
      defaultLanguages[entry.key] = m.defaultLanguage!;
    }
    warnings.addAll(m.warnings);
    // Membership is what the model file says, gathered per provider so the
    // provider knows what it serves and which of them leads.
    servedBy.putIfAbsent(m.profile.provider, () => <String>[]).add(entry.key);
  }

  // Only models whose provider is configured can be reached, so membership and
  // usability are the same test: a provider with no settings has nowhere to send
  // a request, and a model naming one is reported rather than silently dropped.
  for (final entry in <String, List<String>>{...servedBy}.entries) {
    if (names.contains(entry.key)) continue;
    for (final alias in entry.value) {
      models.remove(alias);
      defaults.remove(alias);
      pricing.remove(alias);
      voices.remove(alias);
      languages.remove(alias);
      defaultLanguages.remove(alias);
      warnings.add(
        'Model "$alias" names provider "${entry.key}", but no '
        '$kVoiceConfigProvidersDir/${entry.key}.json is loaded, so it is not '
        'available.',
      );
    }
    servedBy.remove(entry.key);
  }

  // Membership sorted so the first model a provider lists is its default, and the
  // list is the only statement of who serves what.
  for (final name in names) {
    final provider = overlay.providers[name] ?? base.providers[name]!;
    final aliases = <String>[...?servedBy[name]]..sort();
    providers[name] = ProviderConfig(
      name: provider.name,
      settings: provider.settings,
      models: aliases,
    );
  }

  return (
    VoiceConfig(
      providers: providers,
      models: models,
      defaults: defaults,
      pricing: pricing,
      voices: voices,
      languages: languages,
      defaultLanguages: defaultLanguages,
    ),
    warnings,
  );
}

/// One layer's provider files, before any merge.
class _ProviderLayer {
  const _ProviderLayer({
    required this.order,
    required this.providers,
    required this.warnings,
  });

  /// Loaded provider names, ordered the way precedence wants them: the first
  /// carrying an `api_key` — a hosted backend — ahead of the ones that need
  /// something running locally, and alphabetical within each group. Cloud before
  /// local is the whole rule; nothing declares it.
  final List<String> order;

  final Map<String, ProviderConfig> providers;

  final List<String> warnings;
}

/// One layer's model files, keyed by alias.
typedef _ParsedModel = ({
  TtsModelProfile profile,
  String? defaultVoice,
  AudioPricing? pricing,
  Map<String, Voice> voices,
  Map<String, String> languages,
  String? defaultLanguage,
  List<String> warnings,
});

/// Reads every provider file in `providers/` of [dir].
///
/// Files are found by walking the directory, so a new provider is a new file.
/// [dir] has no config.json registry to consult; the marker's emptiness is the
/// point (see [kVoiceConfigRegistryName]).
_ProviderLayer _loadProviderLayer(String dir) {
  final separator = Platform.pathSeparator;
  final warnings = <String>[];
  final providersDir = '$dir$separator$kVoiceConfigProvidersDir';
  final providers = <String, ProviderConfig>{};

  for (final file in _jsonFilesIn(providersDir)) {
    final name = _stemOf(file.path);
    try {
      providers[name] = _parseProviderFile(file.path, name);
    } on VoiceConfigurationError catch (e) {
      warnings.add('Skipped provider "$name": ${e.message}');
    }
  }

  // Hosted providers first, so the app starts on one that needs no server
  // running; alphabetically within each group so the order does not depend on
  // directory iteration.
  final cloud = <String>[];
  final local = <String>[];
  for (final name in providers.keys) {
    (providers[name]!.settings.containsKey('api_key') ? cloud : local).add(name);
  }
  cloud.sort();
  local.sort();

  return _ProviderLayer(
    order: [...cloud, ...local],
    providers: providers,
    warnings: warnings,
  );
}

/// Reads every model file in [dir] that is in use on [platformTag].
///
/// A model file directly in `models/` is in use everywhere, and one in
/// `models/`[platformTag] only there, so the platform a model belongs to is
/// where its file sits rather than a field inside it. Dropping a file in is the
/// whole of adding a model — nothing else lists it.
///
/// [platformTag] null reads every platform's directory at once, for a caller
/// inspecting the config as data rather than as this machine's configuration.
/// When a platform-specific file shadows a top-level one of the same name, the
/// specific one wins: it is the narrower statement about the same model.
({Map<String, _ParsedModel> models, List<String> warnings}) _loadModelLayer(
  String dir,
  String? platformTag,
) {
  final models = <String, _ParsedModel>{};
  final warnings = <String>[..._warnUnknownModelDirs(dir)];
  final separator = Platform.pathSeparator;
  final modelsDir = '$dir$separator$kVoiceConfigModelsDir';

  void read(Iterable<File> files) {
    for (final file in files) {
      final alias = _stemOf(file.path);
      try {
        models[alias] = _parseModelFile(file.path, alias);
      } on VoiceConfigurationError catch (e) {
        warnings.add('Skipped model "$alias": ${e.message}');
      }
    }
  }

  // Read the platform-specific files first and let the top-level ones stand down
  // for an alias already taken: when both exist they are two statements about
  // one model, and the specific one is the one this machine runs. With no
  // platform in hand, every platform's directory is read, so the union holds.
  final tags = platformTag != null && kVoiceConfigPlatformTags.contains(platformTag)
      ? <String>[platformTag]
      : kVoiceConfigPlatformTags;
  for (final tag in tags) {
    read(_jsonFilesIn('$modelsDir$separator$tag'));
  }
  read(
    _jsonFilesIn(modelsDir).where(
      (f) => !models.containsKey(_stemOf(f.path)),
    ),
  );

  return (models: models, warnings: warnings);
}

/// `*.json` files directly in [dir], sorted by path so loads are deterministic.
List<File> _jsonFilesIn(String dir) {
  final entry = Directory(dir);
  if (!entry.existsSync()) return const [];
  final files =
      entry
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// Reports subdirectories of `models/` that are not platform tags.
///
/// A model file in one of those is served nowhere, and reading nothing where a
/// model was meant to be is the failure worth naming. A platform subdirectory
/// that this load is not serving is not a mistake, so it is left quiet.
Iterable<String> _warnUnknownModelDirs(String dir) sync* {
  final entry = Directory('$dir${Platform.pathSeparator}$kVoiceConfigModelsDir');
  if (!entry.existsSync()) return;
  for (final child in entry.listSync()) {
    if (child is! Directory) continue;
    final name = _stemOf(child.path);
    if (kVoiceConfigPlatformTags.contains(name)) continue;
    yield
        '"$kVoiceConfigModelsDir/$name" is not a platform tag '
        '(${kVoiceConfigPlatformTags.toList()..sort()}), so the model files in '
        'it are ignored.';
  }
}

ProviderConfig _parseProviderFile(String path, String name) {
  final raw = _readJson(path);
  if (raw is! Map<String, dynamic>) {
    throw VoiceConfigurationError('must be a JSON object');
  }

  final settingsOut = <String, String>{};
  final settingsRaw = raw['settings'];
  if (settingsRaw != null) {
    if (settingsRaw is! Map<String, dynamic>) {
      throw VoiceConfigurationError('"settings" must be an object');
    }
    settingsRaw.forEach((key, value) {
      if (value is! String) {
        throw VoiceConfigurationError('"settings.$key" must be a string');
      }
      settingsOut[key] = value;
    });
  }

  // Membership is not a provider's to state: model files name their provider and
  // loadVoiceConfig collects what each one serves. So this read yields settings
  // only, and the caller fills the rest in.
  return ProviderConfig(name: name, settings: settingsOut, models: const []);
}

/// The fields a `voices` entry object may carry. An entry naming no `id` is
/// read as keyed by its own key, so only an entry made entirely of fields
/// outside this set is treated as a mistake rather than an annotation.
const _voiceEntryFields = {'id', 'name', 'gender', 'language'};

// A whole `voices` block may also be a bare list of ids, read in
/// _parseModelFile: a list entry has no key to be filed under, so it cannot use
/// this codec.

/// Decodes one `voices` entry: the [key] it is filed under and its raw [value].
///
/// On failure returns the reason, phrased as the tail of a "Voice ... is
/// skipped: ..." warning.
///
/// An entry that says nothing about its id keeps the key-as-id reading. One that
/// carries only unknown fields is a config mistake — most often a mistyped "id" —
/// and guessing would narrate in the wrong voice instead of failing where the
/// config can name the mistake.
({Voice? voice, String? problem}) voiceFromEntry(String key, Object? value) {
  if (value is String) {
    if (value.isEmpty) {
      return (voice: null, problem: 'its voice id is empty.');
    }
    return (voice: Voice(id: value), problem: null);
  }
  if (value is! Map<String, dynamic>) {
    return (
      voice: null,
      problem: 'it is neither a voice id nor a voice object.',
    );
  }
  final rawId = value['id'];
  if (rawId != null && (rawId is! String || rawId.isEmpty)) {
    return (voice: null, problem: 'its "id" is not a non-empty string.');
  }
  if (rawId == null && value.keys.any((k) => !_voiceEntryFields.contains(k))) {
    return (
      voice: null,
      problem:
          'it names no "id" and its only '
          '${value.keys.length == 1 ? 'field is' : 'fields are'} '
          '${value.keys.map((k) => '"$k"').join(", ")}, which this config '
          'schema does not define.',
    );
  }
  final rawName = value['name'];
  final rawLanguage = value['language'];
  return (
    voice: Voice(
      id: rawId ?? key,
      name: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : null,
      gender: parseVoiceGender(
        value['gender'] is String ? value['gender'] : null,
      ),
      language: rawLanguage is String && rawLanguage.trim().isNotEmpty
          ? rawLanguage.trim()
          : null,
    ),
    problem: null,
  );
}

/// The JSON for one `voices` entry, in the shape it was most likely authored in.
///
/// The round-trip form [VoiceConfigStore] writes back, and the mirror of
/// [voiceFromEntry].
Map<String, Object?> voiceEntryJson(String key, Voice voice) => {
  // An entry keyed by its own id needs no `id`; one keyed by a name does.
  if (voice.id != key) 'id': voice.id,
  if (voice.name != null) 'name': voice.name,
  if (voice.gender != null) 'gender': voice.gender!.label,
  if (voice.language != null) 'language': voice.language,
};

/// Reads the output formats a model file offers, most-preferred first.
///
/// Required: a model that does not declare what it can produce cannot be
/// configured for a run, and guessing would hand the user a container the
/// backend never produces and fail on the first segment.
///
/// `sample_rate` is deliberately not read — the rate is either inside the WAV or
/// stated in the response's content type, so a config key for it has nothing left
/// to configure. Files carrying it still load unchanged.
List<TtsAudioFormat> _parseFormats(Map<String, dynamic> raw, String alias) {
  final declared = raw['formats'];
  if (declared == null) {
    throw VoiceConfigurationError(
      'Model "$alias" needs a "formats" list naming what it can produce '
      '(expected ${TtsAudioFormat.values.map((f) => '"${f.wireValue}"').join(' or ')})',
    );
  }
  if (declared is! List || declared.isEmpty) {
    throw VoiceConfigurationError(
      '"formats" must be a non-empty list of format names '
      '(${TtsAudioFormat.values.map((f) => '"${f.wireValue}"').join(' or ')})',
    );
  }
  final formats = <TtsAudioFormat>[];
  for (final entry in declared) {
    if (entry is! String) {
      throw VoiceConfigurationError('"formats" entries must be strings');
    }
    final format = TtsAudioFormat.tryParse(entry);
    if (format == null) {
      throw VoiceConfigurationError(
        '"formats" entry "$entry" is not a supported format '
        '(expected ${TtsAudioFormat.values.map((f) => '"${f.wireValue}"').join(' or ')})',
      );
    }
    // Repeats would show a duplicated button in the format picker.
    if (!formats.contains(format)) formats.add(format);
  }
  return formats;
}

/// Reads the `response_format` to send when a run's output format is wav.
///
/// Optional and defaults to `wav`: writing the provider's finished container
/// through untouched is the path that cannot mislabel anything. A backend that
/// serves only headerless samples declares `pcm` instead.
///
/// Declaring it on a model with no wav format is rejected rather than ignored,
/// since it describes a wav request that would never be made — almost always a
/// copy-paste left over from a model that did offer wav.
TtsWavResponseFormat _parseWavResponseFormat(
  Map<String, dynamic> raw,
  String alias,
  List<TtsAudioFormat> formats,
) {
  final declared = raw['wav_response_format'];
  if (declared == null) return TtsWavResponseFormat.wav;
  if (declared is! String) {
    throw VoiceConfigurationError('"wav_response_format" must be a string');
  }
  final format = TtsWavResponseFormat.tryParse(declared);
  if (format == null) {
    throw VoiceConfigurationError(
      'Model "$alias" declares an unsupported "wav_response_format" '
      '"$declared" (expected '
      '${TtsWavResponseFormat.values.map((f) => '"${f.wireValue}"').join(' or ')})',
    );
  }
  if (!formats.contains(TtsAudioFormat.wav)) {
    throw VoiceConfigurationError(
      'Model "$alias" declares "wav_response_format" but its "formats" list '
      'does not include "wav", so no wav request would ever be made',
    );
  }
  return format;
}

({
  TtsModelProfile profile,
  String? defaultVoice,
  AudioPricing? pricing,
  Map<String, Voice> voices,
  Map<String, String> languages,
  String? defaultLanguage,
  List<String> warnings,
})
/// Reads one model file: the model it declares, and the provider that serves it.
///
/// The file names its own provider, which is the other half of making a model by
/// adding a file: `models/<alias>.json` says what the model is, `"provider"`
/// says who answers for it, and neither `config.json` nor any provider file has
/// to be touched to add the next one.
///
/// A missing or blank `"provider"` is fatal here rather than defaulted. Guessing
/// one would send the request somewhere it cannot be routed, and failing here
/// names the key that is missing.
_parseModelFile(String path, String alias) {
  // Per-entry problems are collected, not thrown: one unusable voice should not
  // cost the whole model, but must not vanish silently either.
  final warnings = <String>[];
  void skip(String key, String because) =>
      warnings.add('Voice "$key" in model "$alias" is skipped: $because');
  final raw = _readJson(path);
  if (raw is! Map<String, dynamic>) {
    throw VoiceConfigurationError('must be a JSON object');
  }
  final id = raw['id'];
  if (id is! String || id.isEmpty) {
    throw VoiceConfigurationError('needs a non-empty "id"');
  }
  final provider = raw['provider'];
  if (provider is! String || provider.trim().isEmpty) {
    throw VoiceConfigurationError(
      'needs a non-empty "provider" naming the '
      '$kVoiceConfigProvidersDir file that serves it',
    );
  }
  final formats = _parseFormats(raw, alias);
  final wavResponseFormat = _parseWavResponseFormat(raw, alias, formats);
  final promptStyle = raw['prompt_style'];
  if (promptStyle != null && promptStyle is! bool) {
    throw VoiceConfigurationError('"prompt_style" must be a bool');
  }
  final sendsVoice = raw['sends_voice'];
  if (sendsVoice != null && sendsVoice is! bool) {
    throw VoiceConfigurationError('"sends_voice" must be a bool');
  }
  final supportsSpeed = raw['speed'];
  if (supportsSpeed != null && supportsSpeed is! bool) {
    throw VoiceConfigurationError('"speed" must be a bool');
  }
  final sendsLanguage = raw['sends_language'];
  if (sendsLanguage != null && sendsLanguage is! bool) {
    throw VoiceConfigurationError('"sends_language" must be a bool');
  }
  final sendsInstruct = raw['sends_instruct'];
  if (sendsInstruct != null && sendsInstruct is! bool) {
    throw VoiceConfigurationError('"sends_instruct" must be a bool');
  }
  final sendsReferenceAudio = raw['sends_reference_audio'];
  if (sendsReferenceAudio != null && sendsReferenceAudio is! bool) {
    throw VoiceConfigurationError('"sends_reference_audio" must be a bool');
  }
  final defaultInstructRaw = raw['default_instruct'];
  if (defaultInstructRaw != null && defaultInstructRaw is! String) {
    throw VoiceConfigurationError('"default_instruct" must be a string');
  }
  final displayName = raw['display_name'];
  if (displayName != null && displayName is! String) {
    throw VoiceConfigurationError('"display_name" must be a string');
  }
  final voicesEditable = raw['voices_editable'];
  if (voicesEditable != null && voicesEditable is! bool) {
    throw VoiceConfigurationError('"voices_editable" must be a bool');
  }

  String? defaultVoice;
  final defaultVoiceRaw = raw['default_voice'];
  if (defaultVoiceRaw != null) {
    if (defaultVoiceRaw is! String || defaultVoiceRaw.trim().isEmpty) {
      throw VoiceConfigurationError(
        '"default_voice" must be a non-empty string',
      );
    }
    defaultVoice = defaultVoiceRaw;
  }

  AudioPricing? pricing;
  final pricingRaw = raw['pricing'];
  if (pricingRaw != null) {
    if (pricingRaw is! Map<String, dynamic>) {
      throw VoiceConfigurationError('"pricing" must be an object');
    }
    pricing = AudioPricing(
      inputUsdPerMTokens: _num(pricingRaw['input_usd_per_m_tokens']),
      outputUsdPerMTokens: _num(pricingRaw['output_usd_per_m_tokens']),
      usdPerMChars: _num(pricingRaw['usd_per_m_chars']),
    );
  }

  final voices = <String, Voice>{};
  final voicesRaw = raw['voices'];
  if (voicesRaw is List) {
    // A bare list of voice ids, for a model whose ids are already the labels the
    // picker should show (Gemini's thirty named voices). An id is its own key, so
    // it needs no fields; anything more wants the object form.
    if (voicesRaw.isEmpty) {
      throw VoiceConfigurationError(
        '"voices" is an empty list, so the model would offer no voices',
      );
    }
    for (final id in voicesRaw) {
      if (id is! String || id.isEmpty) {
        // `skip` quotes the name it is given, so non-strings are encoded rather than
        // interpolated, where a number would read as ""42"".
        skip(
          id is String ? id : jsonEncode(id),
          'a voice id in a "voices" list must be a non-empty string.',
        );
        continue;
      }
      voices[id] = Voice(id: id);
    }
  } else if (voicesRaw is Map<String, dynamic>) {
    voicesRaw.forEach((key, value) {
      final entry = voiceFromEntry(key, value);
      final voice = entry.voice;
      if (voice == null) {
        skip(key, entry.problem!);
        return;
      }
      voices[key] = voice;
    });
  } else if (voicesRaw != null) {
    throw VoiceConfigurationError(
      '"voices" must be an object or a list of voice ids',
    );
  }

  final languages = <String, String>{};
  final languagesRaw = raw['languages'];
  if (languagesRaw != null) {
    if (languagesRaw is! Map<String, dynamic>) {
      throw VoiceConfigurationError(
        '"languages" must be an object of code → label',
      );
    }
    languagesRaw.forEach((code, label) {
      if (code.isEmpty || label is! String || label.trim().isEmpty) {
        throw VoiceConfigurationError(
          '"languages" must map non-empty codes to non-blank string labels',
        );
      }
      languages[code] = label;
    });
  }

  String? defaultLanguage;
  final defaultLanguageRaw = raw['default_language'];
  if (defaultLanguageRaw != null) {
    if (defaultLanguageRaw is! String || defaultLanguageRaw.isEmpty) {
      throw VoiceConfigurationError('"default_language" must be a string');
    }
    if (!languages.containsKey(defaultLanguageRaw)) {
      throw VoiceConfigurationError(
        '"default_language" is "$defaultLanguageRaw", which is not a code in '
        '"languages" (${languages.keys.isEmpty ? "none declared" : languages.keys.join(", ")})',
      );
    }
    defaultLanguage = defaultLanguageRaw;
  }

  return (
    profile: TtsModelProfile(
      alias: alias,
      id: id,
      formats: formats,
      wavResponseFormat: wavResponseFormat,
      promptStyle: promptStyle ?? false,
      sendsVoiceField: sendsVoice ?? true,
      supportsSpeed: supportsSpeed ?? false,
      sendsLanguageField: sendsLanguage ?? false,
      sendsInstructField: sendsInstruct ?? false,
      sendsReferenceAudioField: sendsReferenceAudio ?? false,
      provider: provider,
      displayName: displayName,
      defaultInstruct: defaultInstructRaw as String?,
      voicesEditable: voicesEditable ?? false,
    ),
    defaultVoice: defaultVoice,
    pricing: pricing,
    voices: voices,
    languages: languages,
    defaultLanguage: defaultLanguage,
    warnings: warnings,
  );
}

/// The raw JSON object of the model file for [alias] in [configDir], with the
/// user's overlay file shadowing the downloaded one.
///
/// Returns null when no layer holds the model, and throws
/// [VoiceConfigurationError] when the file exists but is not a JSON object —
/// substituting an empty one would let a save destroy what the user wrote.
///
/// The map is the file as it stands, unknown keys and all, so an editor can
/// change one part and put the rest back. That is why this exists instead of
/// re-emitting a [TtsModelProfile], which is a lossy view of a schema the app
/// only partly understands.
///
/// [platformTag] picks which file of a model that ships both everywhere and on
/// one platform is being read, so this answers the same question the loader does.
Map<String, dynamic>? readModelJson(
  String configDir,
  String alias, {
  String? platformTag,
}) {
  for (final path in modelFileCandidates(configDir, alias, platformTag: platformTag)) {
    if (!File(path).existsSync()) continue;
    final raw = _readJson(path);
    if (raw is! Map<String, dynamic>) {
      throw VoiceConfigurationError(
        'Invalid voice config "$path": top-level value must be a JSON object',
      );
    }
    return raw;
  }
  return null;
}

/// Every path [alias] could be at in [configDir], most specific first.
///
/// The user's layer before the downloaded one, and within each the
/// platform-specific placement before the top-level one, mirroring how
/// [loadVoiceConfig] resolves a model. A caller that resolved its candidate
/// order differently from the loader would read one file and load another, which
/// is the kind of mismatch that shows up only as an edit that did not take.
List<String> modelFileCandidates(
  String configDir,
  String alias, {
  String? platformTag,
}) {
  final separator = Platform.pathSeparator;
  final platformDir =
      platformTag != null && kVoiceConfigPlatformTags.contains(platformTag)
      ? '$separator$platformTag'
      : '';
  final layers = <String>[
    '$configDir$separator$kVoiceConfigOverlayDirName',
    configDir,
  ];
  return <String>[
    for (final layer in layers)
      '$layer$separator$kVoiceConfigModelsDir$platformDir$separator$alias.json',
    for (final layer in layers)
      '$layer$separator$kVoiceConfigModelsDir$separator$alias.json',
  ];
}

Object? _readJson(String path) {
  try {
    return jsonDecode(File(path).readAsStringSync());
  } on FormatException catch (e) {
    throw VoiceConfigurationError('Invalid voice config "$path": ${e.message}');
  } on IOException catch (e) {
    throw VoiceConfigurationError('Cannot read voice config "$path": $e');
  }
}

String _stemOf(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot == -1 ? name : name.substring(0, dot);
}

/// Converts a JSON numeric value to a double, or null for non-numbers.
double? _num(Object? v) => v is num ? v.toDouble() : null;
