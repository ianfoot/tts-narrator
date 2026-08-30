import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Read-only access to the shared `voice_config.json` used by both the GUI and
/// the headless CLI. The GUI never modifies this file — it's the user's file,
/// optionally copied from `voice_config.example.json`, and edited by the user
/// directly or via the CLI.
class ConfigService {
  ConfigService({String? path}) : path = path ?? defaultConfigPath();

  /// Absolute path of the voice config file.
  final String path;

  /// Reads the current config (empty when the file is absent).
  VoiceConfig load() => loadVoiceConfig(path);
}