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
/// the app downloads and never rewrites. `user/` holds the same layout one
/// level down and belongs to the user: [loadVoiceConfig] reads it as a second
/// layer over the baseline, and [VoiceConfigStore] writes only here. A file in
/// `user/models/` shadows its counterpart in `models/`; a file in
/// `user/providers/` shadows the provider of the same name.
const String kVoiceConfigOverlayDirName = 'user';

/// Loads a [VoiceConfig] from a config *directory* ([configDir]).
///
/// Reads `config.json` for the ordered provider registry, then one
/// `providers/<name>.json` per registered provider, then one
/// `models/<alias>.json` per model those providers serve. A provider file
/// lists the models it provides, so which block a model belongs to is stated
/// once, in the provider file, and the loader inverts that into the `provider`
/// on each model profile.
///
/// Those three file kinds make the *shipped* layer. A second layer, read from
/// [kVoiceConfigOverlayDirName] and shaped identically, is the user's: it is
/// loaded on top and each file it holds replaces its counterpart, so the
/// baseline stays untouched and re-downloadable. Overlay providers are
/// registered first, which is how a user promotes one to the default.
/// Everything is merged before the result is built, so from here on a
/// [VoiceConfig] cannot tell which layer any part came from -- except in
/// warning text, where an overlay problem is prefixed so it can be traced.
///
/// A missing `config.json` yields no providers, and therefore no models: the
/// registry is the entry point. A model file no provider claims is ignored
/// silently -- it is not configuration this config uses. A provider listed in
/// `config.json` whose file or whose models are missing, and a provider file
/// that no registry names, are each reported as warnings.
///
/// A model file that parses keeps every usable part of itself, so one bad voice
/// entry is skipped on its own -- reported as a warning like any other -- rather
/// than costing the whole model.
///
/// If the config directory is missing, this returns an empty config. Fetching
/// defaults is the caller's decision: await `downloadVoiceConfigFiles()`
/// explicitly first if you want them.
///
/// Returns the loaded config plus warnings for anything skipped or broken.
(VoiceConfig, List<String>) loadVoiceConfig(String configDir) {
  // Note: download is no longer triggered automatically here so
  // loadVoiceConfig stays pure synchronous disk I/O. Callers that
  // want remote defaults should await downloadVoiceConfigFiles()
  // explicitly before loading.

  if (!Directory(configDir).existsSync()) {
    return (const VoiceConfig(), <String>[]);
  }
  final overlayDir =
      '$configDir${Platform.pathSeparator}$kVoiceConfigOverlayDirName';

  final base = _loadProviderLayer(configDir);
  // A provider the base registry already names needs no entry in the overlay
  // registry in order to be overridden there, so base names count as named.
  // _warnUnregisteredProviderFiles then skips them: to the overlay layer they
  // are not the stray file the warning is about, they are the name its own
  // registry already gives a home to.
  final overlay = _loadProviderLayer(
    overlayDir,
    alsoRegistered: base.order.toSet(),
  );

  // Whichever layer claims an alias first decides who serves it, and a user's
  // claim outranks the baseline's. Claims are merged before any model file is
  // read, so a model the overlay switches on is readable from either layer.
  final claimedBy = <String, String>{...base.claimedBy, ...overlay.claimedBy};
  final baseModels = _loadModelLayer(configDir, claimedBy);
  final overlayModels = _loadModelLayer(overlayDir, claimedBy);

  final warnings = <String>[
    ...base.warnings,
    ...overlay.warnings.map((w) => 'Overlay: $w'),
    ...baseModels.warnings,
    ...overlayModels.warnings.map((w) => 'Overlay: $w'),
  ];

  // Only providers the overlay's *own* registry names are promoted, because
  // being first decides the default provider and so the model a launch starts
  // on. An inherited override -- user/providers/local.json with no
  // user/config.json beside it -- is an edit to a provider already in use, and
  // must not silently move it ahead of the baseline's first entry. A name in
  // both layers resolves to the overlay file either way.
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

  /// The subset of [order] this layer's *own* registry named.
  ///
  /// Only these may be promoted ahead of the baseline: the registry is the
  /// documented way to reorder providers and change the default, whereas an
  /// inherited override is just an edit to a provider already in use.
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
/// [alsoRegistered] names providers that [dir] does not have to register for
/// itself — a layer inherits the registry of the one it shadows. A name in that
/// set is loaded only when its file is actually present, so an overlay can
/// override a downloaded provider by dropping a file in its place without
/// repeating the name in a second registry, and without inventing a "missing
/// provider file" warning for every provider it chose not to override.
///
/// A name the layer's *own* registry lists that this set also holds is a
/// different case: re-listing a provider the baseline already serves is a
/// redundant entry, not a broken one, because the shadowed copy answers for it.
/// That is suppressed too, so copying a registry and adding to it -- what the
/// README tells a user to do -- warns about nothing at all.
_ProviderLayer _loadProviderLayer(
  String dir, {
  Set<String> alsoRegistered = const {},
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
      // A name this layer did not register is simply not its business. A name
      // it did register is a mistake to report -- unless the layer being
      // shadowed already serves it, in which case the registry entry here is
      // redundant rather than broken and the shadowed copy is the one in use.
      if (!isOwn || alsoRegistered.contains(name)) continue;
      warnings.add(
        'Provider "$name" is listed in config.json but '
        '$kVoiceConfigProvidersDir/$name.json is missing.',
      );
      continue;
    }
    try {
      final provider = _parseProviderFile(path, name);
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
    // No provider claims this alias, so the file is not part of this config.
    // Skipping quietly is deliberate: the models directory may hold packs the
    // user has not switched on.
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
/// Order is the whole point of this file: the first registered provider is
/// the default, and its first model is the default model. The list is
/// preserved exactly, so a user controls the default by ordering rather than
/// by a separate key or by how filenames happen to sort.
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
/// Dropping a file into `providers/` is not enough to switch a provider on,
/// and failing silently there would look like the file was ignored by mistake.
/// [alsoRegistered] holds names a neighbouring layer registers, which is how an
/// overlay file overriding a shipped provider avoids a warning it cannot fix.
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

ProviderConfig _parseProviderFile(String path, String name) {
  final raw = _readJson(path);
  if (raw is! Map<String, dynamic>) {
    throw VoiceConfigurationError('must be a JSON object');
  }

  final modelsRaw = raw['models'];
  final models = <String>[];
  if (modelsRaw is List) {
    for (final entry in modelsRaw) {
      if (entry is! String || entry.trim().isEmpty) {
        throw VoiceConfigurationError('"models" must hold non-empty aliases');
      }
      final alias = entry.trim();
      if (!models.contains(alias)) models.add(alias);
    }
  } else if (modelsRaw != null) {
    throw VoiceConfigurationError('"models" must be a list of model aliases');
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

  return ProviderConfig(name: name, settings: settingsOut, models: models);
}

/// The fields a `voices` entry object may carry. An entry naming no `id` is
/// read as keyed by its own key, so only an entry made entirely of fields
/// outside this set is treated as a mistake rather than an annotation.
const _voiceEntryFields = {'id', 'name', 'gender', 'language'};

// Note that a whole `voices` block may also be a bare list of ids, which is read
// in _parseModelFile rather than here: a list entry has no key to be keyed by,
// so it cannot come through this per-entry codec at all.

/// Decodes one `voices` entry: the [key] it is filed under and its raw [value].
///
/// On success returns the voice; on failure returns the reason, phrased to read
/// as the tail of a "Voice ... is skipped: ..." warning.
///
/// The key is the voice id unless the entry spells one out, so a config can key
/// voices by the id that is unique and name them inside.
///
/// An entry that says nothing about its id keeps the key-as-id reading. An entry
/// that carries only fields this schema does not know is a config mistake --
/// most often a mistyped "id" -- and guessing there would send the key to the
/// provider as a voice id, narrating in the wrong voice instead of failing here
/// where the config can name the mistake.
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
/// An entry keyed by its own id needs no `id` back, so writing one is noise; a
/// name-tagged one does, or the key would become the id on the next load. This
/// is the round-trip form, used by [writeVoiceConfig], which re-emits a config
/// that already parsed.
Map<String, Object?> voiceEntryJson(String key, Voice voice) => {
  // An entry keyed by its own id needs no `id`; one keyed by a name does.
  if (voice.id != key) 'id': voice.id,
  if (voice.name != null) 'name': voice.name,
  if (voice.gender != null) 'gender': voice.gender!.label,
  if (voice.language != null) 'language': voice.language,
};

/// Reads the output formats a model file offers, most-preferred first.
///
/// Required. A model that does not declare what it can produce is a model the
/// app cannot configure a run for, so it is rejected rather than given a
/// default: guessing would hand the user a container the backend never produces
/// and fail on the first segment.
///
/// `sample_rate` is deliberately not read. The rate is either inside the WAV the
/// provider returns or stated in its response's content type, so a config key
/// for it has nothing left to configure. Files that still carry it load
/// unchanged, and the key is ignored like any other the app does not model.
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
  // Per-entry problems are collected rather than thrown: one unusable voice
  // should not cost the whole model, but it must not vanish silently either.
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
    // A bare list of voice ids, for a model whose ids are already the labels
    // the picker should show -- Gemini's thirty named voices, where writing
    // each id twice would say the same thing in two places. An id is its own
    // key, so it needs no id, name or gender of its own; anything it wanted to
    // carry would be the object form, which stays available.
    if (voicesRaw.isEmpty) {
      throw VoiceConfigurationError(
        '"voices" is an empty list, so the model would offer no voices',
      );
    }
    for (final id in voicesRaw) {
      if (id is! String || id.isEmpty) {
        // `skip` quotes the name it is given, so a string is handed over as it is
        // and anything else is encoded rather than interpolated: a number would
        // otherwise read as ""42"", and an empty string as """", neither of
        // which tells the author what to fix.
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
/// [VoiceConfigurationError] when the file exists but is not a JSON object --
/// there is nothing an editor can do with it, and silently substituting an
/// empty one would let a save destroy whatever the user had written.
///
/// The map is the file as it stands, unknown keys and all, so an editor can
/// change one part of it and put the rest back untouched. That is why this
/// exists instead of re-emitting a [TtsModelProfile]: the profile is a lossy
/// view of a schema the app only partly understands.
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
  // Always the object form, even for a model that shipped the bare list: the
  // parser accepts either, and one writer shape keeps this file readable
  // against the editor's output. A list round-trips to id-keyed entries, so
  // nothing is lost -- only the brevity.
  if (config.voices[p.alias] != null && config.voices[p.alias]!.isNotEmpty)
    'voices': {
      for (final e in config.voices[p.alias]!.entries)
        e.key: voiceEntryJson(e.key, e.value),
    },
  if (p.voicesEditable) 'voices_editable': p.voicesEditable,
};

/// Writes [config] to [configDir] in the layout [loadVoiceConfig] reads.
///
/// The provider order in [VoiceConfig.providers] is preserved, since it decides
/// the default. Each provider file carries the aliases it serves, taken from
/// [config.models] -- so a config assembled without an explicit `models` list
/// per provider still round-trips, because every model profile knows its own
/// `provider`.
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
