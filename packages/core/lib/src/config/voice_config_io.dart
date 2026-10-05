import 'dart:convert';
import 'dart:io';

import '../narration/cost.dart';
import '../narration/model_profiles.dart';
import 'voice_config.dart';
import 'voice_config_download.dart';

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

/// Loads a [VoiceConfig] from a config *directory* ([configDir]).
///
/// Reads `config.json` for the ordered provider registry, then one
/// `providers/<name>.json` per registered provider, then one
/// `models/<alias>.json` per model those providers serve. A provider file
/// lists the models it provides, so which block a model belongs to is stated
/// once, in the provider file, and the loader inverts that into the `provider`
/// on each model profile.
///
/// A missing `config.json` yields no providers, and therefore no models: the
/// registry is the entry point. A model file no provider claims is ignored
/// silently -- it is not configuration this config uses. A provider listed in
/// `config.json` whose file or whose models are missing, and a provider file
/// that `config.json` does not register, are each reported as warnings.
///
/// A model file that parses keeps every usable part of itself, so one bad voice
/// entry is skipped on its own -- reported as a warning like any other -- rather
/// than costing the whole model.
///
/// If files don't exist, [downloadVoiceConfigFiles] fetches them from GitHub.
///
/// Returns the loaded config plus warnings for anything skipped or broken.
(VoiceConfig, List<String>) loadVoiceConfig(String configDir) {
  // Note: download is no longer triggered automatically here so
  // loadVoiceConfig stays pure synchronous disk I/O. Callers that
  // want remote defaults should await downloadVoiceConfigFiles()
  // explicitly before loading.

  final warnings = <String>[];
  final separator = Platform.pathSeparator;
  final providersDir = Directory(configDir);
  if (!providersDir.existsSync()) {
    return (const VoiceConfig(), warnings);
  }

  final registered = _loadRegistry(
    '$configDir$separator$kVoiceConfigRegistryName',
  );
  final providers = <String, ProviderConfig>{};
  // Alias -> provider name, inverted from the provider files' model lists.
  final claimedBy = <String, String>{};

  for (final name in registered) {
    final path =
        '$configDir$separator$kVoiceConfigProvidersDir$separator$name.json';
    if (!File(path).existsSync()) {
      warnings.add(
        'Provider "$name" is listed in config.json but '
        '$kVoiceConfigProvidersDir/$name.json is missing.',
      );
      continue;
    }
    try {
      final provider = _parseProviderFile(path, name);
      providers[name] = provider;
      for (final alias in provider.models) {
        claimedBy.putIfAbsent(alias, () => name);
      }
    } on VoiceConfigurationError catch (e) {
      warnings.add('Skipped provider "$name": ${e.message}');
    }
  }

  warnings.addAll(_warnUnregisteredProviderFiles(configDir, providers));

  final models = <String, TtsModelProfile>{};
  final defaults = <String, String>{};
  final pricing = <String, AudioPricing>{};
  final voices = <String, Map<String, Voice>>{};
  final languages = <String, Map<String, String>>{};
  final defaultLanguages = <String, String>{};

  final modelsDir = '$configDir$separator$kVoiceConfigModelsDir';
  for (final file in _jsonFilesIn(modelsDir)) {
    final alias = _stemOf(file.path);
    // No provider claims this alias, so the file is not part of this config.
    // Skipping quietly is deliberate: the models directory may hold packs the
    // user has not switched on.
    final providerName = claimedBy[alias];
    if (providerName == null) continue;
    try {
      final m = _parseModelFile(file.path, alias, providerName);
      models[alias] = m.profile;
      if (m.defaultVoice != null) defaults[alias] = m.defaultVoice!;
      if (m.pricing != null) pricing[alias] = m.pricing!;
      if (m.voices.isNotEmpty) voices[alias] = m.voices;
      if (m.languages.isNotEmpty) languages[alias] = m.languages;
      if (m.defaultLanguage != null) {
        defaultLanguages[alias] = m.defaultLanguage!;
      }
      warnings.addAll(m.warnings);
    } on VoiceConfigurationError catch (e) {
      warnings.add('Skipped model "$alias": ${e.message}');
    }
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

/// Reports provider files present on disk that `config.json` never registers.
///
/// Dropping a file into `providers/` is not enough to switch a provider on,
/// and failing silently there would look like the file was ignored by mistake.
Iterable<String> _warnUnregisteredProviderFiles(
  String configDir,
  Map<String, ProviderConfig> providers,
) sync* {
  final dir = '$configDir${Platform.pathSeparator}$kVoiceConfigProvidersDir';
  for (final file in _jsonFilesIn(dir)) {
    final stem = _stemOf(file.path);
    if (providers.containsKey(stem)) continue;
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
const _voiceEntryFields = {'id', 'name', 'gender'};

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
  void skip(String key, String because) => warnings.add(
    'Voice "$key" in model "$alias" is skipped: $because',
  );
  final raw = _readJson(path);
  if (raw is! Map<String, dynamic>) {
    throw VoiceConfigurationError('must be a JSON object');
  }
  final id = raw['id'];
  if (id is! String || id.isEmpty) {
    throw VoiceConfigurationError('needs a non-empty "id"');
  }
  final format = raw['format'];
  if (format != null && format is! String) {
    throw VoiceConfigurationError('"format" must be a string');
  }
  final sampleRate = raw['sample_rate'];
  if (sampleRate != null && sampleRate is! num) {
    throw VoiceConfigurationError('"sample_rate" must be a number');
  }
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
  final displayName = raw['display_name'];
  if (displayName != null && displayName is! String) {
    throw VoiceConfigurationError('"display_name" must be a string');
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
  if (voicesRaw != null) {
    if (voicesRaw is! Map<String, dynamic>) {
      throw VoiceConfigurationError('"voices" must be an object');
    }
    voicesRaw.forEach((key, value) {
      if (value is String) {
        if (value.isNotEmpty) {
          voices[key] = Voice(id: value);
        } else {
          skip(key, 'its voice id is empty.');
        }
        return;
      }
      if (value is! Map<String, dynamic>) {
        skip(key, 'it is neither a voice id nor a voice object.');
        return;
      }
      // The key is the voice id unless the entry spells one out, so a config can
      // key voices by the id that is unique and name them inside.
      //
      // An entry that says nothing about its id keeps the key-as-id reading.
      // An entry that carries only fields this schema does not know is a config
      // mistake -- most often a mistyped "id" -- and guessing there would send
      // the key to the provider as a voice id, narrating in the wrong voice
      // instead of failing here where the config can name the mistake.
      final rawId = value['id'];
      if (rawId != null && (rawId is! String || rawId.isEmpty)) {
        skip(key, 'its "id" is not a non-empty string.');
        return;
      }
      if (rawId == null &&
          value.keys.any((k) => !_voiceEntryFields.contains(k))) {
        skip(
          key,
          'it names no "id" and its only '
              '${value.keys.length == 1 ? 'field is' : 'fields are'} '
              '${value.keys.map((k) => '"$k"').join(", ")}, which this config '
              'schema does not define.',
        );
        return;
      }
      final rawName = value['name'];
      voices[key] = Voice(
        id: rawId ?? key,
        name: rawName is String && rawName.trim().isNotEmpty
            ? rawName.trim()
            : null,
        gender: parseVoiceGender(
          value['gender'] is String ? value['gender'] : null,
        ),
      );
    });
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
      format: format ?? 'mp3',
      promptStyle: promptStyle ?? false,
      sendsVoiceField: sendsVoice ?? true,
      supportsSpeed: supportsSpeed ?? false,
      sendsLanguageField: sendsLanguage ?? false,
      sampleRate: sampleRate?.toInt(),
      provider: provider,
      displayName: displayName,
    ),
    defaultVoice: defaultVoice,
    pricing: pricing,
    voices: voices,
    languages: languages,
    defaultLanguage: defaultLanguage,
    warnings: warnings,
  );
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
  if (p.format != 'mp3') 'format': p.format,
  if (p.sampleRate != null) 'sample_rate': p.sampleRate,
  if (p.promptStyle) 'prompt_style': p.promptStyle,
  if (!p.sendsVoiceField) 'sends_voice': p.sendsVoiceField,
  if (p.supportsSpeed) 'speed': p.supportsSpeed,
  if (p.sendsLanguageField) 'sends_language': p.sendsLanguageField,
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
  if (config.voices[p.alias] != null && config.voices[p.alias]!.isNotEmpty)
    'voices': {
      for (final e in config.voices[p.alias]!.entries)
        e.key: {
          // An entry keyed by its own id needs no `id`; one keyed by a name does.
          if (e.value.id != e.key) 'id': e.value.id,
          if (e.value.name != null) 'name': e.value.name,
          if (e.value.gender != null) 'gender': e.value.gender!.label,
        },
    },
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
