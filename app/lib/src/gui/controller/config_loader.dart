import 'dart:io';

import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Loads the shared config directory (CLI + GUI use the same layout, the GUI
/// read-only) and resolves the bits a run config needs: the effective models,
/// the default voice, pricing, and the provider settings block with `${ENV}`
/// references expanded from the runtime environment.
class UserVoiceConfigLoader {
  UserVoiceConfigLoader({String? configDir}) : configDir = configDir;

  /// Absolute path of the config directory (defaults to the platform path).
  final String? configDir;

  /// Warnings from the last [load] (e.g. a skipped malformed model file).
  List<String> warnings = const [];

  /// Creates a loader with the default config directory from path_provider.
  static Future<UserVoiceConfigLoader> create() async =>
      UserVoiceConfigLoader(configDir: await defaultConfigDir());

  /// Resolves the config directory, using the provided value or fetching from
  /// path_provider if null.
  Future<String> _resolveConfigDir() async =>
      configDir ?? await defaultConfigDir();

  /// Reads the config; empty when the directory is absent.
  Future<VoiceConfig> load() async {
    final dir = await _resolveConfigDir();
    final (cfg, warnings) = loadVoiceConfig(dir);
    this.warnings = warnings;
    return cfg;
  }

  /// The resolved provider settings block for [profile] (see `resolveSettings`).
  Future<Map<String, String>> resolveProviderSettings(
    TtsModelProfile profile,
  ) async => resolveSettings(
    (await load()).providers[profile.provider] ?? const {},
    env: Platform.environment,
  );
}
