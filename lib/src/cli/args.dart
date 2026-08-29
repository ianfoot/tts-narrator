import '../narration/config.dart';

/// All 30 Gemini TTS voices.
const kVoices = [
  'Zephyr', 'Puck', 'Charon', 'Kore', 'Fenrir', 'Leda', 'Orus', 'Aoede',
  'Callirrhoe', 'Autonoe', 'Enceladus', 'Iapetus', 'Umbriel', 'Algieba',
  'Despina', 'Erinome', 'Algenib', 'Rasalgethi', 'Laomedeia', 'Achernar',
  'Alnilam', 'Schedar', 'Gacrux', 'Pulcherrima', 'Achird', 'Zubenelgenubi',
  'Vindemiatrix', 'Sadachbia', 'Sadaltager', 'Sulafat',
];

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
  var voice = 'Charon';
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
  if (!kVoices.contains(voice)) {
    throw CliUsageError(
      'Unknown voice "$voice". Available: ${kVoices.join(', ')}',
    );
  }

  return NarrationConfig(
    inputPath: input,
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
  --voice <name>            One of the 30 voices (default: Charon).
  --accent <text>           Accent description in prompt (default: "southern
                            British English, neutral and clear").
  --style <text>            Style/register description in prompt (default: "warm,
                            composed, restrained, literary").
  --tags on|off             Prepend a [calm] tag (default: off).
  --passage-prefix <text>   Pooled preamble applied to each paragraph.
  --min-words <n>           Merge paragraphs shorter than n words into the next
                            (default: 30).
  --sample-len <n>          Narrate only the first n paragraphs.
  --dry-run                 Print the chunk plan and exit (no API call).
  --out <dir>               Output directory (default: "output").
  --api-key <key>           OpenRouter API key (defaults to OPENROUTER_API_KEY).

Outputs <voice-slug>_<nn>.wav and manifest.json into <out>.
Example:
  dart run bin/main.dart --input /path/to/text.txt --voice Charon --sample-len 1
''';