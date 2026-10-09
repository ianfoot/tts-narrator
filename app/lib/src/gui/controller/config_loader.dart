import 'dart:io';

import 'package:tts_narrator_core/tts_narrator_core.dart';

// Prefixed so the [UserVoiceConfigLoader.platformTag] field can default from the
// detected platform without the two names colliding in the initializer list.
import '../platform/platform_detection.dart' as platform;

/// Loads the shared config directory (read-only) and resolves the bits a run
/// config needs: the effective models, the default voice, pricing, and the
/// provider settings block with `${ENV}` references expanded from the runtime
/// environment.
class UserVoiceConfigLoader {
  UserVoiceConfigLoader({
    required this.configDir,
    Map<String, String>? environment,
    String? platformTag,
  }) : environment = environment ?? Platform.environment,
       platformTag = platformTag ?? platform.platformTag;

  /// Absolute path of the config directory.
  final String configDir;

  /// The environment `${ENV}` references in the provider block resolve against.
  /// Defaults to the process environment; injectable so tests never
  /// depend on what the host shell happens to export.
  final Map<String, String> environment;

  /// The platform tag (`macos` / `linux` / `windows`) that selects which models
  /// a provider file claims when its `models` block is a per-platform map.
  /// Defaults to the detected platform; injectable so tests can read a config
  /// as another platform would without running on it.
  ///
  /// This has to be threaded rather than left out: `config.json` is one global
  /// registry, so `providers/*.json` lands on every platform. Read without a
  /// tag, a provider that gates its models would claim every platform's and warn
  /// about macOS-only ones on Linux -- where the download step correctly never
  /// fetched them, so the warning described a state that cannot exist.
  final String platformTag;

  /// Warnings from the last [load] (e.g. a skipped malformed model file).
  List<String> warnings = const [];

  /// Reads the config from [configDir]; empty when the directory is absent.
  VoiceConfig load() {
    final (cfg, warnings) = loadVoiceConfig(
      configDir,
      platformTag: platformTag,
    );
    this.warnings = warnings;
    return cfg;
  }

  /// The resolved provider settings block for [profile] (see `resolveSettings`).
  ///
  /// [overrides] are merged over the raw `settings` block from the model's
  /// `providers/<name>.json` before `${ENV}` expansion, so a caller can
  /// substitute a value the environment could not provide (e.g. a key from the
  /// OS secure store). An unresolved `${ENV}` still throws the core `StateError`.
  Map<String, String> resolveProviderSettings(
    TtsModelProfile profile, {
    Map<String, String>? overrides,
  }) => resolveSettings({
    ...load().providers[profile.provider]?.settings ?? const {},
    ...?overrides,
  }, env: environment);
}
