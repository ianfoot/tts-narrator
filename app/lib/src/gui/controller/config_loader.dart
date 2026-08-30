import 'dart:io';

import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Loads the shared `voice_config.json` (CLI + GUI use the same file, the GUI
/// read-only) and resolves the bits a run config needs: the effective models,
/// the default voice, pricing, and the provider settings block with `${ENV}`
/// references expanded from the runtime environment.
class VoiceConfigLoader {
  VoiceConfigLoader({String? configPath})
      : configPath = configPath ?? defaultConfigPath();

  /// Absolute path of the voice config file (defaults to the platform path).
  final String configPath;

  /// Reads the config; empty when the file is absent.
  VoiceConfig load() => loadVoiceConfig(configPath);

  /// The resolved provider settings block for [profile] (see `resolveSettings`).
  Map<String, String> resolveProviderSettings(TtsModelProfile profile) =>
      resolveSettings(
        load().providers[profile.provider] ?? const {},
        env: Platform.environment,
      );
}