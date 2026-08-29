import '../narration/config.dart';
import '../narration/model_profiles.dart';

/// Thrown when the user provides invalid CLI arguments.
class CliUsageError implements Exception {
  CliUsageError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Parses command-line arguments into a [NarrationConfig].
///
/// `--input` is required (no default filenames). Unknown flags and malformed
/// values raise [CliUsageError].
NarrationConfig parseArgs(List<String> args) {
  String? input;
  var profile = kGeminiProfile;
  var voice = kGeminiProfile.defaultVoice;
  var accent = 'southern British English, neutral and clear';
  var style = 'warm, composed, restrained, literary';
  var tags = false;
  var prefix =
      'Narrate this passage for an audiobook. You are a warm, composed female narrator.';
  var minWords = 30;
  var sampleLen = -1;
  var outDir = 'output';
  var dryRun = false;
  String? apiKey;

  var i = 0;
  String take(String flag) {
    if (i + 1 >= args.length) {
      throw CliUsageError('Missing value for $flag.');
    }
    i++;
    return args[i];
  }

  for (; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--input':
        input = take(arg);
      case '--model':
        final v = take(arg);
        final resolved = profileFor(v);
        if (resolved == null) {
          throw CliUsageError(
            'Unknown model "$v". Available: ${kModelProfiles.values.map((p) => p.alias).join(', ')} '
            '(or pass a full model id).',
          );
        }
        profile = resolved;
        if (voice == kGeminiProfile.defaultVoice) {
          voice = profile.defaultVoice;
        }
      case '--voice':
        voice = take(arg);
      case '--accent':
        accent = take(arg);
      case '--style':
        style = take(arg);
      case '--passage-prefix':
        prefix = take(arg);
      case '--out':
        outDir = take(arg);
      case '--api-key':
        apiKey = take(arg);
      case '--sample-len':
        final v = take(arg);
        final n = int.tryParse(v);
        if (n == null || n < 1) {
          throw CliUsageError('--sample-len must be a positive integer, got "$v".');
        }
        sampleLen = n;
      case '--min-words':
        final v = take(arg);
        final n = int.tryParse(v);
        if (n == null || n < 1) {
          throw CliUsageError('--min-words must be a positive integer, got "$v".');
        }
        minWords = n;
      case '--dry-run':
        dryRun = true;
      case '--tags':
        final v = take(arg);
        if (v == 'off' || v == 'false' || v == '0') {
          tags = false;
        } else if (v == 'on' || v == 'true' || v == '1') {
          tags = true;
        } else {
          throw CliUsageError('--tags must be on or off, got "$v".');
        }
      case '--help':
      case '-h':
        throw CliUsageError(usage);
      default:
        if (arg.startsWith('-')) {
          throw CliUsageError('Unknown flag: $arg');
        }
        throw CliUsageError('Unexpected positional argument: $arg');
    }
  }

  if (input == null || input.trim().isEmpty) {
    throw CliUsageError('--input <path> is required (no default filename).');
  }
  if (!profile.voiceFreeForm && !profile.voices.contains(voice)) {
    throw CliUsageError(
      'Unknown voice "$voice" for ${profile.alias}. Available: '
      '${profile.voices.join(', ')}',
    );
  }

  return NarrationConfig(
    inputPath: input,
    profile: profile,
    voice: voice,
    accent: accent,
    style: style,
    useCalmTag: tags,
    passagePrefix: prefix,
    minWords: minWords,
    sampleLen: sampleLen > 0 ? sampleLen : null,
    outDir: outDir,
    dryRun: dryRun,
    apiKey: apiKey,
  );
}

const usage = '''
Usage: dart run bin/main.dart --input <path> [options]

Required:
  --input <path>            Path to the text to narrate (no default).

Options:
  --model <alias|id>        TTS model: gemini (default) or kokoro, or a full
                            model id. Controls voice set, prompt styling, and
                            output format.
  --voice <name>            Model-specific voice. For gemini: one of its 30
                            named voices (default: Charon). For kokoro: a
                            provider voice id such as bf_emma or bm_lewis;
                            any id is accepted (prefix a=_US, b=_British).
  --accent <text>           Accent description folded into the prompt
                            (gemini only; ignored by kokoro).
  --style <text>            Style/register description in prompt (gemini only;
                            ignored by kokoro).
  --tags on|off             Prepend a [calm] tag (gemini only; default: off).
  --passage-prefix <text>   Pooled preamble applied to each paragraph.
  --min-words <n>           Merge paragraphs shorter than n words into the next
                            (default: 30).
  --sample-len <n>          Narrate only the first n paragraphs.
  --dry-run                 Print the chunk plan and exit (no API call).
  --out <dir>               Output directory (default: "output").
  --api-key <key>           OpenRouter API key (defaults to OPENROUTER_API_KEY).

Output format follows the model: gemini writes <voice>_<nn>.wav (24 kHz PCM),
kokoro writes <voice>_<nn>.mp3.
Example:
  dart run bin/main.dart --input /path/to/text.txt --voice Charon --sample-len 1
  dart run bin/main.dart --input /path/to/text.txt --model kokoro --voice bf_emma
''';