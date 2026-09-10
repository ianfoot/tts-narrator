import 'dart:convert';
import 'dart:io';

import '../narration/cost.dart';
import '../narration/model_profiles.dart';
import 'voice_config.dart';
import 'voice_config_download.dart';
import 'voice_config_queries.dart';

/// Default config directory, shared by the CLI and GUI.
String defaultConfigDir() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    return appData != null ? '$appData\\tts-narrator' : 'tts-narrator';
  }
  final home = Platform.environment['HOME'];
  return home != null ? '$home/.config/tts-narrator' : '.';
}

/// Loads a [VoiceConfig] from a config *directory* ([configDir]).
///
/// Reads `config.json` for the global `default_model` + `providers` block,
/// then one ``<alias>.json`` file per model directly in the directory. A
/// missing `config.json` yields empty global data; a directory with no model
/// files yields no configured models.
///
/// If files don't exist, [downloadVoiceConfigFiles] fetches them from GitHub.
///
/// Returns the loaded config plus warnings for skipped models.
(VoiceConfig, List<String>) loadVoiceConfig(String configDir) {
  // Note: download is no longer triggered automatically here so
  // loadVoiceConfig stays pure synchronous disk I/O. Callers that
  // want remote defaults should await downloadVoiceConfigFiles()
  // explicitly before loading.

  final warnings = <String>[];
  final separator = Platform.pathSeparator;
  final global = File('$configDir${separator}config.json');
  final globalConfig = global.existsSync()
      ? _loadGlobalConfig(global.path)
      : const VoiceConfig();

  final configDirEntry = Directory(configDir);
  if (!configDirEntry.existsSync()) return (globalConfig, warnings);

  final files =
      configDirEntry
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.json'))
          .where((f) => !f.path.toLowerCase().endsWith('config.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final models = <String, TtsModelProfile>{};
  final defaults = <String, String>{};
  final pricing = <String, AudioPricing>{};
  final voices = <String, Map<String, Voice>>{};
  for (final f in files) {
    final alias = _stemOf(f.path);
    try {
      final m = _parseModelFile(f.path, alias);
      models[alias] = m.profile;
      if (m.defaultVoice != null) defaults[alias] = m.defaultVoice!;
      if (m.pricing != null) pricing[alias] = m.pricing!;
      if (m.voices.isNotEmpty) voices[alias] = m.voices;
    } on VoiceConfigurationError catch (e) {
      warnings.add('Skipped model "$alias": ${e.message}');
    }
  }

  final config = VoiceConfig(
    defaultModel: globalConfig.defaultModel,
    providers: globalConfig.providers,
    models: models,
    defaults: defaults,
    pricing: pricing,
    voices: voices,
  );

  final configuredDefault = config.defaultModel;
  if (configuredDefault != null &&
      configuredDefault.trim().isNotEmpty &&
      profileFor(configuredDefault.trim(), config) == null) {
    warnings.add(
      'default_model "$configuredDefault" is not a configured model; '
      'falling back to the compiled default.',
    );
  }

  return (config, warnings);
}

VoiceConfig _loadGlobalConfig(String path) {
  final raw = _readJson(path);
  if (raw is! Map<String, dynamic>) {
    throw VoiceConfigurationError(
      'Invalid voice config "$path": top-level value must be a JSON object',
    );
  }
  final defaultModelRaw = raw['default_model'];
  if (defaultModelRaw != null && defaultModelRaw is! String) {
    throw VoiceConfigurationError(
      'Invalid voice config "$path": "default_model" must be a string',
    );
  }
  final providersOut = <String, Map<String, String>>{};
  final providersRaw = raw['providers'];
  if (providersRaw is Map<String, dynamic>) {
    providersRaw.forEach((id, settings) {
      if (settings is! Map<String, dynamic>) {
        throw VoiceConfigurationError(
          'Invalid voice config "$path": "providers.$id" must be an object',
        );
      }
      final out = <String, String>{};
      settings.forEach((key, value) {
        if (value is! String) {
          throw VoiceConfigurationError(
            'Invalid voice config "$path": "providers.$id.$key" must be a '
            'string',
          );
        }
        out[key] = value;
      });
      providersOut[id] = out;
    });
  }
  return VoiceConfig(
    defaultModel: defaultModelRaw as String?,
    providers: providersOut,
  );
}

({
  TtsModelProfile profile,
  String? defaultVoice,
  AudioPricing? pricing,
  Map<String, Voice> voices,
}) _parseModelFile(String path, String alias) {
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
  final provider = raw['provider'];
  if (provider is! String || provider.trim().isEmpty) {
    throw VoiceConfigurationError('needs a non-empty "provider"');
  }
  final displayName = raw['display_name'];
  if (displayName != null && displayName is! String) {
    throw VoiceConfigurationError('"display_name" must be a string');
  }

  String? defaultVoice;
  final defaultVoiceRaw = raw['default_voice'];
  if (defaultVoiceRaw != null) {
    if (defaultVoiceRaw is! String || defaultVoiceRaw.trim().isEmpty) {
      throw VoiceConfigurationError('"default_voice" must be a non-empty string');
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
    voicesRaw.forEach((label, value) {
      if (value is String) {
        if (value.isNotEmpty) voices[label] = Voice(id: value);
        return;
      }
      if (value is! Map<String, dynamic>) return;
      final id = value['id'];
      if (id is! String || id.isEmpty) return;
      voices[label] = Voice(
        id: id,
        gender: parseVoiceGender(
          value['gender'] is String ? value['gender'] : null,
        ),
      );
    });
  }

  return (
    profile: TtsModelProfile(
      alias: alias,
      id: id,
      format: format ?? 'mp3',
      promptStyle: promptStyle ?? false,
      sendsVoiceField: sendsVoice ?? true,
      sampleRate: sampleRate?.toInt(),
      provider: provider.trim(),
      displayName: displayName,
    ),
    defaultVoice: defaultVoice,
    pricing: pricing,
    voices: voices,
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
  'provider': p.provider,
  if (p.displayName != null) 'display_name': p.displayName,
  if (p.format != 'mp3') 'format': p.format,
  if (p.sampleRate != null) 'sample_rate': p.sampleRate,
  if (p.promptStyle) 'prompt_style': p.promptStyle,
  if (!p.sendsVoiceField) 'sends_voice': p.sendsVoiceField,
  if (config.defaults[p.alias] != null)
    'default_voice': config.defaults[p.alias],
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
          'id': e.value.id,
          if (e.value.gender != null) 'gender': e.value.gender!.label,
        },
    },
};

void writeVoiceConfig(String configDir, VoiceConfig config) {
  final globalJson = <String, Object?>{
    if (config.defaultModel != null) 'default_model': config.defaultModel,
    if (config.providers.isNotEmpty) 'providers': config.providers,
  };
  try {
    File('$configDir${Platform.pathSeparator}config.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(globalJson),
        flush: true,
      );
  } on FileSystemException catch (e) {
    throw VoiceConfigurationError('Cannot write voice config "$configDir": $e');
  }

  if (config.models.isEmpty) return;
  Directory(configDir).createSync(recursive: true);
  for (final entry in config.models.entries) {
    final modelJson = _modelJson(entry.value, config);
    try {
      File('$configDir${Platform.pathSeparator}${entry.key}.json')
          .writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(modelJson),
            flush: true,
          );
    } on FileSystemException catch (e) {
      throw VoiceConfigurationError('Cannot write voice config "$configDir": $e');
    }
  }
}

/// Converts a JSON numeric value to a double, or null for non-numbers.
double? _num(Object? v) => v is num ? v.toDouble() : null;
