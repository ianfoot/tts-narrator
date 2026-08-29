import 'dart:convert';
import 'dart:io';

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

/// Default config file location: ~/.config/tts-narrator/voice_config.json .
String defaultConfigPath() {
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

/// Thrown when the voice config file exists but is unreadable or malformed.
class VoiceConfigError implements Exception {
  VoiceConfigError(this.message);
  final String message;

  @override
  String toString() => message;
}