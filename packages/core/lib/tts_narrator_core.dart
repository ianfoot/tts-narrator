/// Public API for the pure-Dart TTS narration core.
///
/// The GUI (`app/`) imports this single barrel instead of reaching into
/// `src/`, so internal layout can change without breaking consumers.
library;

export 'src/config/voice_config.dart';
export 'src/config/voice_config_download.dart';
export 'src/config/voice_config_io.dart';
export 'src/config/voice_config_queries.dart';
export 'src/narration/abort.dart';
export 'src/narration/config.dart';
export 'src/narration/concat.dart';
export 'src/narration/cost.dart';
export 'src/narration/model_profiles.dart';
export 'src/narration/model_ui.dart';
export 'src/narration/narration.dart';
export 'src/narration/prompt.dart';
export 'src/narration/tts_provider.dart';
export 'src/narration/wav.dart';
