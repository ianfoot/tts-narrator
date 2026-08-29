import 'dart:convert';
import 'dart:io';

import '../narration/model_profiles.dart';

/// A single selectable voice for the GUI voice picker and CLI listing.
class VoiceEntry {
  const VoiceEntry({
    required this.model,
    required this.id,
    required this.label,
    required this.isAlias,
  });

  /// Model alias this voice belongs to (e.g. `gemini`, `fish`).
  final String model;

  /// Provider voice id sent in the request body.
  final String id;

  /// Human-readable label: the friendly alias when [isAlias], else the raw id.
  final String label;

  /// Whether [label] is a friendly alias from the config (vs a raw id).
  final bool isAlias;
}

/// Friendly-name aliases for TTS voices, loaded from a single JSON file.
///
/// Schema:
///   {
///     "api_key": "sk-or-...",            // optional
///     "voices": {
///       "fish":   { "British Female Narrator": "89f41ea2..." },
///       "kokoro": { "Emma": "bf_emma" }
///     }
///   }
///
/// The file is optional: when no default config exists and `--config` was not
/// given, an empty config is used and every feature degrades gracefully
/// (raw voice ids pass through, api key falls back to env).
class VoiceConfig {
  const VoiceConfig({this.apiKey, this.aliases = const {}});

  /// Optional OpenRouter API key from the config file.
  final String? apiKey;

  /// Friendly-name → provider voice id, keyed by model alias.
  final Map<String, Map<String, String>> aliases;

  bool get isEmpty => apiKey == null && aliases.isEmpty;

  /// Resolves a `--voice` value to the provider voice id for [modelAlias].
  ///
  /// If [value] matches a friendly alias for the model, the mapped raw id is
  /// returned. Otherwise the value is returned unchanged (free-form ids and
  /// raw id passthrough keep working exactly as before).
  (String id, String label) resolveVoice(String modelAlias, String value) {
    final modelAliases = aliases[modelAlias];
    if (modelAliases != null) {
      final id = modelAliases[value];
      if (id != null) return (id, value);
    }
    return (value, value);
  }
}

/// All selectable voices for [model] (or all models when null), combining the
/// profile's known voices with friendly aliases from [config].
///
/// The default voice is always included (deduplicated if it also appears as a
/// known voice or alias). Free-form models still surface any curated profile
/// voices — free-form only means the id list is not exhaustive.
List<VoiceEntry> voiceEntries({
  TtsModelProfile? model,
  required VoiceConfig config,
}) {
  final profiles = model != null ? [model] : kModelProfiles.values.toList();
  final entries = <VoiceEntry>[];
  for (final p in profiles) {
    final aliases = config.aliases[p.alias] ?? const <String, String>{};

    void add(String id, String label, bool isAlias) {
      if (entries.any((e) => e.model == p.alias && e.id == id)) return;
      entries.add(VoiceEntry(model: p.alias, id: id, label: label, isAlias: isAlias));
    }

    for (final v in p.voices) {
      add(v, v, false);
    }
    aliases.forEach((label, id) => add(id, label, true));
    add(p.defaultVoice, p.defaultVoice, false);
  }
  entries.sort((a, b) {
    final byModel = a.model.compareTo(b.model);
    if (byModel != 0) return byModel;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return entries;
}

/// Default config file location, shared by the CLI and GUI.
///
/// macOS/Linux: `~/.config/tts-narrator/voice_config.json`
/// Windows:     `%APPDATA%\tts-narrator\voice_config.json`
String defaultConfigPath() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    return appData != null
        ? '$appData\\tts-narrator\\voice_config.json'
        : 'voice_config.json';
  }
  final home = Platform.environment['HOME'];
  final base = home != null ? '$home/.config/tts-narrator' : '.';
  return '$base/voice_config.json';
}

/// Loads a [VoiceConfig] from [path].
///
/// Throws a [VoiceConfigError] when the file exists but can't be read or
/// parsed. A missing file (whether default or explicitly requested) yields an
/// empty config — `--config` pointing at a bad file should still fail loudly
/// on read errors, which is handled by the caller.
VoiceConfig loadVoiceConfig(String path) {
  final file = File(path);
  if (!file.existsSync()) return const VoiceConfig();
  try {
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('top-level value must be a JSON object');
    }
    final apiKey = raw['api_key'];
    if (apiKey != null && apiKey is! String) {
      throw const FormatException('"api_key" must be a string');
    }

    final voicesOut = <String, Map<String, String>>{};
    final voices = raw['voices'];
    if (voices is Map<String, dynamic>) {
      voices.forEach((model, aliases) {
        final modelAliases = <String, String>{};
        if (aliases is Map<String, dynamic>) {
          aliases.forEach((label, id) {
            if (id is String && id.isNotEmpty) modelAliases[label] = id;
          });
        }
        if (modelAliases.isNotEmpty) voicesOut[model] = modelAliases;
      });
    }
    return VoiceConfig(
      apiKey: apiKey as String?,
      aliases: voicesOut,
    );
  } on FormatException catch (e) {
    throw VoiceConfigError('Invalid voice config "$path": ${e.message}');
  } on IOException catch (e) {
    throw VoiceConfigError('Cannot read voice config "$path": $e');
  }
}

/// Writes [config] to [path] as the shared `voice_config.json` schema,
/// creating parent directories as needed. Round-trips `api_key` and the
/// per-model voice aliases so the CLI and GUI serialize identically.
///
/// Throws a [VoiceConfigError] when the file cannot be written.
void writeVoiceConfig(String path, VoiceConfig config) {
  final json = <String, Object?>{
    if (config.apiKey != null) 'api_key': config.apiKey,
    if (config.aliases.isNotEmpty) 'voices': config.aliases,
  };
  try {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
  } on FileSystemException catch (e) {
    throw VoiceConfigError('Cannot write voice config "$path": $e');
  }
}

/// Thrown when the voice config file exists but is unreadable or malformed,
/// or when a write fails.
class VoiceConfigError implements Exception {
  VoiceConfigError(this.message);
  final String message;

  @override
  String toString() => message;
}