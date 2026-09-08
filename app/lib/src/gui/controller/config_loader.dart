import 'dart:io';

import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Loads the shared config directory (CLI + GUI use the same layout, the GUI
/// read-only) and resolves the bits a run config needs: the effective models,
/// the default voice, pricing, and the provider settings block with `${ENV}`
/// references expanded from the runtime environment.
class UserVoiceConfigLoader {
  UserVoiceConfigLoader({String? configDir})
    : configDir = configDir ?? defaultConfigDir();

  /// Absolute path of the config directory (defaults to the platform path).
  final String configDir;

  /// Warnings from the last [load] (e.g. a skipped malformed model file).
  List<String> warnings = const [];

  /// Reads the config; empty when the directory is absent.
  VoiceConfig load() {
    final (cfg, warnings) = loadVoiceConfig(configDir);
    this.warnings = warnings;
    return cfg;
  }

  /// The resolved provider settings block for [profile] (see `resolveSettings`).
  Map<String, String> resolveProviderSettings(TtsModelProfile profile) =>
      resolveSettings(
        load().providers[profile.provider] ?? const {},
        env: Platform.environment,
      );
}
