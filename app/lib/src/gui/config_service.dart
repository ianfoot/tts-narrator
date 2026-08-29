import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Loads/saves the shared `voice_config.json` used by both the GUI and the
/// headless CLI, so aliases and the api key stay in one place.
class ConfigService {
  ConfigService({String? path}) : path = path ?? defaultConfigPath();

  /// Absolute path of the voice config file.
  final String path;

  /// Reads the current config (empty when the file is absent).
  VoiceConfig load() => loadVoiceConfig(path);

  /// Persists [config] to [path], throwing [VoiceConfigError] on failure.
  void save(VoiceConfig config) => writeVoiceConfig(path, config);
}