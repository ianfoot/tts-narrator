import 'dart:io';

import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Loads the shared config directory (CLI + GUI use the same layout, the GUI
/// read-only) and resolves the bits a run config needs: the effective models,
/// the default voice, pricing, and the provider settings block with `${ENV}`
/// references expanded from the runtime environment.
class UserVoiceConfigLoader {
  UserVoiceConfigLoader({
    String? configDir,
    Map<String, String>? environment,
  }) : configDir = configDir ?? defaultConfigDir(),
       environment = environment ?? Platform.environment;

  /// Absolute path of the config directory (defaults to the platform path).
  final String configDir;

  /// The environment `${ENV}` references in the provider block resolve against.
  /// Defaults to the process environment; injectable so tests never
  /// depend on what the host shell happens to export.
  final Map<String, String> environment;

  /// Warnings from the last [load] (e.g. a skipped malformed model file).
  List<String> warnings = const [];

  /// Reads the config from [configDir]; empty when the directory is absent.
  VoiceConfig load() {
    final (cfg, warnings) = loadVoiceConfig(configDir);
    this.warnings = warnings;
    return cfg;
  }

  /// The resolved provider settings block for [profile] (see `resolveSettings`).
  ///
  /// [overrides] are merged over the raw `settings` block from the model's
  /// `providers/<name>.json` before `${ENV}` expansion, so a caller can
  /// substitute a value (e.g. a key from the OS secure store) for a setting the
  /// environment could not provide. An unresolved `${ENV}` reference still
  /// throws the core `StateError`.
  Map<String, String> resolveProviderSettings(
    TtsModelProfile profile, {
    Map<String, String>? overrides,
  }) => resolveSettings({
    ...load().providers[profile.provider]?.settings ?? const {},
    ...?overrides,
  }, env: environment);
}
