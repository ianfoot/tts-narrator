/// Public API for the pure-Dart TTS narration core.
///
/// The GUI (`app/`) and the CLI (`packages/cli/`) both import this single
/// barrel instead of reaching into `src/`, so internal layout can change
/// without breaking consumers.
library;

export 'src/cli/args.dart';
export 'src/cli/voice_config.dart';
export 'src/narration/abort.dart';
export 'src/narration/config.dart';
export 'src/narration/cost.dart';
export 'src/narration/model_profiles.dart';
export 'src/narration/narration.dart';