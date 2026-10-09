import 'dart:convert';
import 'dart:io';

import '../narration/audio_format.dart';
import '../narration/cost.dart';
import '../narration/model_profiles.dart';
import 'voice_config.dart';

/// Default config directory, shared by the CLI and GUI.
String defaultConfigDir() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    return appData != null ? '$appData\\tts-narrator' : 'tts-narrator';
  }
  final home = Platform.environment['HOME'];
  return home != null ? '$home/.config/tts-narrator' : '.';
}

/// File name of the provider registry, in the config directory root.
const String kVoiceConfigRegistryName = 'config.json';

/// Subdirectory of the config directory holding one `<name>.json` per provider.
const String kVoiceConfigProvidersDir = 'providers';

/// Subdirectory of the config directory holding one `<alias>.json` per model.
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
/// Single source of truth for the tag strings, which name the same concept in
/// both places a platform appears: the keys of `manifest.json`'s `platforms`
/// block (see [ManifestVoiceConfig]) and the keys of a provider file's
/// per-platform `models` map. They live here rather than beside the manifest
/// because the loader has to know the tags even when no manifest is in play.
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
/// Reads `config.json` for the ordered provider registry, then one
/// `providers/<name>.json` per registered provider, then one
/// `models/<alias>.json` per model those providers serve. A provider file lists
/// the models it provides, so membership is stated once and the loader inverts it
/// into the `provider` on each model profile.
///
/// Those three file kinds make the *shipped* layer. A second layer, read from
/// [kVoiceConfigOverlayDirName] and shaped identically, is the user's: loaded on
/// top, each file it holds replacing its counterpart, so the baseline stays
/// untouched and re-downloadable. Overlay providers are registered first, which
/// is how a user promotes one to the default. Everything is merged before the
/// result is built, so a [VoiceConfig] cannot tell which layer a part came from
/// — except in warning text, where an overlay problem is prefixed so it can be
/// traced.
///
/// A missing `config.json` yields no providers, and therefore no models. A model
/// file no provider claims is ignored silently — it is not configuration this
/// config uses. A listed provider whose file or models are missing, and a
/// provider file no registry names, are reported as warnings. A model file that
/// parses keeps every usable part of itself, so one bad voice entry costs only
/// itself.
///
/// If the config directory is missing, this returns an empty config. Fetching
/// defaults is the caller's decision: await `downloadVoiceConfigFiles()`
/// explicitly first if you want them.
///
/// [platformTag] selects which models a provider file claims when its `models`
/// block is a per-platform map. Providers themselves are not gated: `config.json`
/// is one global registry and `providers/*.json` ships on every platform. Gating
/// the models is what keeps a platform that downloaded a provider but not its
/// model files — macOS-only MLX backends on Linux, say — from reading as a
/// provider claiming missing models. Omit it to have a per-platform map yield
/// every platform's aliases rather than one arbitrary slice.
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

  final base = _loadProviderLayer(configDir, platformTag: platformTag);
  // Base names count as registered for the overlay, so overriding a provider needs
  // no second registry entry and no stray-file warning.
  final overlay = _loadProviderLayer(
    overlayDir,
    alsoRegistered: base.order.toSet(),
    platformTag: platformTag,
  );

  // The first layer to claim an alias serves it, so a user's claim outranks the
  // baseline's. Claims merge before any model file is read, so a model the
  // overlay switches on is readable from either layer.
  final claimedBy = <String, String>{...base.claimedBy, ...overlay.claimedBy};
  final baseModels = _loadModelLayer(configDir, claimedBy);
  final overlayModels = _loadModelLayer(overlayDir, claimedBy);

  final warnings = <String>[
    ...base.warnings,
    ...overlay.warnings.map((w) => 'Overlay: $w'),
    ...baseModels.warnings,
    ...overlayModels.warnings.map((w) => 'Overlay: $w'),
  ];

  // Only providers the overlay's *own* registry names are promoted, since being
  // first decides the default provider and so the model a launch starts on. An
  // inherited override (a provider file with no user/config.json beside it) is an
  // edit to a provider in use, not a request to move it ahead of the baseline.
  final promoted = overlay.promoted;
  final providers = <String, ProviderConfig>{};
  for (final name in <String>[
    ...promoted,
    ...base.order.where((n) => !promoted.contains(n)),
  ]) {
    final provider = overlay.providers[name] ?? base.providers[name];
    if (provider == null) continue;
    providers[name] = provider;
  }

  final models = <String, TtsModelProfile>{};
  final defaults = <String, String>{};
  final pricing = <String, AudioPricing>{};
  final voices = <String, Map<String, Voice>>{};
  final languages = <String, Map<String, String>>{};
  final defaultLanguages = <String, String>{};

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
  }

  for (final entry in providers.entries) {
    for (final alias in entry.value.models) {
      if (models.containsKey(alias)) continue;
      warnings.add(
        'Provider "${entry.key}" lists model "$alias" but '
        '$kVoiceConfigModelsDir/$alias.json is missing or unusable.',
      );
    }
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

/// One layer's registry and provider files, before any merge.
class _ProviderLayer {
  const _ProviderLayer({
    required this.order,
    required this.promoted,
    required this.providers,
    required this.claimedBy,
    required this.warnings,
  });

  /// Loaded provider names, own registry first then inherited.
  final List<String> order;

  /// The subset of [order] this layer's *own* registry named, and so the only
  /// names that may be promoted ahead of the baseline.
  final List<String> promoted;

  final Map<String, ProviderConfig> providers;

  /// Alias -> provider name, inverted from the provider files' model lists.
  final Map<String, String> claimedBy;

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

/// Reads `config.json` and every provider file it registers, in one [dir].
///
/// [alsoRegistered] names providers [dir] need not register for itself — a layer
/// inherits the registry of the one it shadows. A name in that set loads only if
/// its file is present, and neither a missing file nor a re-listing in the layer's
/// own registry warns, since the shadowed copy answers for it either way. That
/// makes the README's "copy the registry and add to it" warn about nothing.
///
/// [platformTag] reaches each provider file's `models` block. The gate is a
/// per-file decision, so it applies per layer rather than merged: an overlay
/// provider file replaces its baseline counterpart wholesale, and the replacing
/// file decides what it claims.
_ProviderLayer _loadProviderLayer(
  String dir, {
  Set<String> alsoRegistered = const {},
  String? platformTag,
}) {
  final separator = Platform.pathSeparator;
  final warnings = <String>[];
  final registered = _loadRegistry('$dir$separator$kVoiceConfigRegistryName');
  final inherited = alsoRegistered.where((n) => !registered.contains(n));
  final order = <String>[];
  final promoted = <String>[];
  final providers = <String, ProviderConfig>{};
  final claimedBy = <String, String>{};

  for (final name in <String>[...registered, ...inherited]) {
    final isOwn = registered.contains(name);
    final path = '$dir$separator$kVoiceConfigProvidersDir$separator$name.json';
    if (!File(path).existsSync()) {
      // An unregistered name is not this layer's business. A registered one is a
      // mistake to report, unless the shadowed layer already serves it.
      if (!isOwn || alsoRegistered.contains(name)) continue;
      warnings.add(
        'Provider "$name" is listed in config.json but '
        '$kVoiceConfigProvidersDir/$name.json is missing.',
      );
      continue;
    }
    try {
      final provider = _parseProviderFile(path, name, platformTag);
      providers[name] = provider;
      order.add(name);
      if (isOwn) promoted.add(name);
      for (final alias in provider.models) {
        claimedBy.putIfAbsent(alias, () => name);
      }
    } on VoiceConfigurationError catch (e) {
      warnings.add('Skipped provider "$name": ${e.message}');
    }
  }

  warnings.addAll(
    _warnUnregisteredProviderFiles(dir, providers, alsoRegistered),
  );
  return _ProviderLayer(
    order: order,
    promoted: promoted,
    providers: providers,
    claimedBy: claimedBy,
    warnings: warnings,
  );
}

/// Reads every model file in [dir] that [claimedBy] says is in use.
({Map<String, _ParsedModel> models, List<String> warnings}) _loadModelLayer(
  String dir,
  Map<String, String> claimedBy,
) {
  final models = <String, _ParsedModel>{};
  final warnings = <String>[];
  final modelsDir = '$dir${Platform.pathSeparator}$kVoiceConfigModelsDir';

  for (final file in _jsonFilesIn(modelsDir)) {
    final alias = _stemOf(file.path);
    // Quietly: the models directory may hold packs the user has not switched on.
    final providerName = claimedBy[alias];
    if (providerName == null) continue;
    try {
      models[alias] = _parseModelFile(file.path, alias, providerName);
    } on VoiceConfigurationError catch (e) {
      warnings.add('Skipped model "$alias": ${e.message}');
    }
  }

  return (models: models, warnings: warnings);
}

/// Reads the ordered provider names out of `config.json`.
///
/// Order is the whole point: the first provider is the default, and its first
/// model the default model. Preserved exactly, so a user controls the default by
/// ordering rather than by a separate key or by filename sort.
List<String> _loadRegistry(String path) {
  if (!File(path).existsSync()) return const [];
  final raw = _readJson(path);
  if (raw is! Map<String, dynamic>) {
    throw VoiceConfigurationError(
      'Invalid voice config "$path": top-level value must be a JSON object',
    );
  }
  final providersRaw = raw['providers'];
  if (providersRaw == null) return const [];
  if (providersRaw is! List) {
    throw VoiceConfigurationError(
      'Invalid voice config "$path": "providers" must be a list of names',
    );
  }
  final names = <String>[];
  for (final entry in providersRaw) {
    if (entry is! String || entry.trim().isEmpty) {
      throw VoiceConfigurationError(
        'Invalid voice config "$path": "providers" must hold non-empty '
        'provider names',
      );
    }
    final name = entry.trim();
    if (!names.contains(name)) names.add(name);
  }
  return names;
}

/// Reports provider files present on disk that no registry names.
///
/// Dropping a file into `providers/` is not enough to switch a provider on, and
/// failing silently would look like the file was ignored by mistake.
/// [alsoRegistered] holds names a neighbouring layer registers, so an overlay
/// overriding a shipped provider avoids a warning it cannot fix.
Iterable<String> _warnUnregisteredProviderFiles(
  String configDir,
  Map<String, ProviderConfig> providers, [
  Set<String> alsoRegistered = const {},
]) sync* {
  final dir = '$configDir${Platform.pathSeparator}$kVoiceConfigProvidersDir';
  for (final file in _jsonFilesIn(dir)) {
    final stem = _stemOf(file.path);
    if (providers.containsKey(stem)) continue;
    if (alsoRegistered.contains(stem)) continue;
    yield 'Provider file "$stem.json" is not listed in config.json and is '
        'ignored; add it to "providers" to use it.';
  }
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

/// Reads the `models` block of a provider file and returns the aliases this
/// platform is served.
///
/// Two shapes are accepted, and the difference is exactly the platform gate:
///
/// - A bare **list**: this provider serves these models on every platform.
/// - A **map** keyed by platform tag: this provider serves these models *here*,
///   and only the entry for [platformTag] is taken. An unnamed tag, or one mapped
///   to an empty list, yields no models — which is how a provider that ships
///   everywhere (`config.json` registers providers globally) serves models on
///   only the platforms that can run them. Every key must be one of
///   [kVoiceConfigPlatformTags], or a typo silently serves nothing where it was
///   meant to serve everything.
///
/// [platformTag] may be null for a caller inspecting the config as data, in which
/// case a per-platform map yields the union of every platform's entry.
List<String> _parseProviderModels(Object? raw, String? platformTag) {
  List<String> readAliases(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw VoiceConfigurationError('"models" must be a list of model aliases');
    }
    final aliases = <String>[];
    for (final entry in value) {
      if (entry is! String || entry.trim().isEmpty) {
        throw VoiceConfigurationError('"models" must hold non-empty aliases');
      }
      final alias = entry.trim();
      if (!aliases.contains(alias)) aliases.add(alias);
    }
    return aliases;
  }

  if (raw is Map<String, dynamic>) {
    // Checked before dispatching, so a typo is reported even when this read is not
    // the one for the tag that was meant.
    for (final tag in raw.keys) {
      if (!kVoiceConfigPlatformTags.contains(tag)) {
        throw VoiceConfigurationError(
          '"models" names unknown platform "$tag"; expected one of '
          '${(kVoiceConfigPlatformTags.toList()..sort()).join(', ')}',
        );
      }
    }
    if (platformTag == null) {
      // Union in map order, so an alias two platforms share appears once.
      final union = <String>[];
      for (final value in raw.values) {
        for (final alias in readAliases(value)) {
          if (!union.contains(alias)) union.add(alias);
        }
      }
      return union;
    }
    return readAliases(raw[platformTag]);
  }

  return readAliases(raw);
}

ProviderConfig _parseProviderFile(
  String path,
  String name,
  String? platformTag,
) {
  final raw = _readJson(path);
  if (raw is! Map<String, dynamic>) {
    throw VoiceConfigurationError('must be a JSON object');
  }

  final models = _parseProviderModels(raw['models'], platformTag);

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

  return ProviderConfig(name: name, settings: settingsOut, models: models);
}

/// The fields a `voices` entry object may carry. An entry naming no `id` is
/// read as keyed by its own key, so only an entry made entirely of fields
/// outside this set is treated as a mistake rather than an annotation.
const _voiceEntryFields = {'id', 'name', 'gender', 'language'};

// A whole `voices` block may also be a bare list of ids, read in _parseModelFile:
  // a list entry has no key to be filed under, so it cannot use this codec.

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
/// The round-trip form used by [writeVoiceConfig], which re-emits a config that
/// already parsed.
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
_parseModelFile(String path, String alias, String provider) {
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
Map<String, dynamic>? readModelJson(String configDir, String alias) {
  final separator = Platform.pathSeparator;
  for (final dir in <String>[
    '$configDir$separator$kVoiceConfigOverlayDirName',
    configDir,
  ]) {
    final path = '$dir$separator$kVoiceConfigModelsDir$separator$alias.json';
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

Map<String, Object?> _modelJson(TtsModelProfile p, VoiceConfig config) => {
  'id': p.id,
  if (p.displayName != null) 'display_name': p.displayName,
  'formats': [for (final f in p.formats) f.wireValue],
  if (p.wavResponseFormat != TtsWavResponseFormat.wav)
    'wav_response_format': p.wavResponseFormat.wireValue,
  if (p.promptStyle) 'prompt_style': p.promptStyle,
  if (!p.sendsVoiceField) 'sends_voice': p.sendsVoiceField,
  if (p.supportsSpeed) 'speed': p.supportsSpeed,
  if (p.sendsLanguageField) 'sends_language': p.sendsLanguageField,
  if (p.sendsInstructField) 'sends_instruct': p.sendsInstructField,
  if (p.defaultInstruct != null && p.defaultInstruct!.isNotEmpty)
    'default_instruct': p.defaultInstruct,
  if (config.defaults[p.alias] != null)
    'default_voice': config.defaults[p.alias],
  if (config.defaultLanguages[p.alias] != null)
    'default_language': config.defaultLanguages[p.alias],
  if ((config.languages[p.alias] ?? const {}).isNotEmpty)
    'languages': {
      for (final e in config.languagesFor(p.alias).entries) e.key: e.value,
    },
  if (config.pricing[p.alias] != null)
    'pricing': {
      if (config.pricing[p.alias]!.usdPerMChars != null)
        'usd_per_m_chars': config.pricing[p.alias]!.usdPerMChars,
      if (config.pricing[p.alias]!.inputUsdPerMTokens != null)
        'input_usd_per_m_tokens': config.pricing[p.alias]!.inputUsdPerMTokens,
      if (config.pricing[p.alias]!.outputUsdPerMTokens != null)
        'output_usd_per_m_tokens': config.pricing[p.alias]!.outputUsdPerMTokens,
    },
  // Always the object form, even for a model that shipped the bare list: the parser
  // accepts either, and one writer shape keeps this file consistent with the
  // editor's output. A list round-trips to id-keyed entries — only brevity is
  // lost.
  if (config.voices[p.alias] != null && config.voices[p.alias]!.isNotEmpty)
    'voices': {
      for (final e in config.voices[p.alias]!.entries)
        e.key: voiceEntryJson(e.key, e.value),
    },
  if (p.voicesEditable) 'voices_editable': p.voicesEditable,
};

/// Writes [config] to [configDir] in the layout [loadVoiceConfig] reads.
///
/// Provider order is preserved, since it decides the default. Each provider file
/// carries the aliases it serves, taken from [config.models], so a config
/// assembled without an explicit per-provider `models` list still round-trips.
void writeVoiceConfig(String configDir, VoiceConfig config) {
  final separator = Platform.pathSeparator;
  final providersDir =
      '$configDir$separator$kVoiceConfigProvidersDir$separator';
  final modelsDir = '$configDir$separator$kVoiceConfigModelsDir$separator';

  final byProvider = <String, List<String>>{};
  for (final entry in config.models.entries) {
    byProvider
        .putIfAbsent(entry.value.provider, () => <String>[])
        .add(entry.key);
  }

  void write(String path, Object? json) {
    try {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(json),
          flush: true,
        );
    } on FileSystemException catch (e) {
      throw VoiceConfigurationError(
        'Cannot write voice config "$configDir": $e',
      );
    }
  }

  write('$configDir$separator$kVoiceConfigRegistryName', {
    'providers': config.providers.keys.toList(),
  });

  for (final entry in config.providers.entries) {
    final declared = entry.value.models;
    final extra = (byProvider[entry.key] ?? const <String>[]).where(
      (a) => !declared.contains(a),
    );
    write('$providersDir${entry.key}.json', {
      'models': [...declared, ...extra],
      'settings': entry.value.settings,
    });
  }

  for (final entry in config.models.entries) {
    write('$modelsDir${entry.key}.json', _modelJson(entry.value, config));
  }
}

/// Converts a JSON numeric value to a double, or null for non-numbers.
double? _num(Object? v) => v is num ? v.toDouble() : null;
