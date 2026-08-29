import 'dart:io';

import '../narration/config.dart';
import '../narration/model_profiles.dart';
import 'voice_config.dart';

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
  var resume = false;
  String? apiKey;
  String? configPath;

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
      case '--config':
        configPath = take(arg);
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
      case '--resume':
        resume = true;
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

  // Voice config: friendly-name aliases + optional api_key.
  final cfgPath = configPath ?? defaultConfigPath();
  if (configPath != null && !File(cfgPath).existsSync()) {
    throw CliUsageError('Voice config file not found: "$cfgPath".');
  }
  final VoiceConfig voiceConfig;
  try {
    voiceConfig = loadVoiceConfig(cfgPath);
  } on VoiceConfigError catch (e) {
    throw CliUsageError('$e');
  }

  // api_key precedence: --api-key flag > config file > OPENROUTER_API_KEY env.
  final configKey = voiceConfig.apiKey;
  if (apiKey == null && configKey != null && configKey.trim().isNotEmpty) {
    apiKey = configKey;
  }

  // Resolve a friendly voice alias (if any) to the provider voice id.
  final (voiceId, voiceLabel) =
      voiceConfig.resolveVoice(profile.alias, voice);
  if (!profile.voiceFreeForm && !profile.voices.contains(voiceId)) {
    throw CliUsageError(
      'Unknown voice "$voiceId" for ${profile.alias}. Available: '
      '${profile.voices.join(', ')}',
    );
  }

  return NarrationConfig(
    inputPath: input,
    profile: profile,
    voice: voiceId,
    voiceLabel: voiceLabel,
    accent: accent,
    style: style,
    useCalmTag: tags,
    passagePrefix: prefix,
    minWords: minWords,
    sampleLen: sampleLen > 0 ? sampleLen : null,
    outDir: outDir,
    dryRun: dryRun,
    resume: resume,
    apiKey: apiKey,
  );
}

/// Expands a single `--input` value into one or more `.txt` files to narrate.
///
/// A regular file yields itself. A directory yields its top-level `*.txt`
/// files, sorted and excluding hidden files. Throws a [CliUsageError] when the
/// path is missing or yields no files.
List<String> expandInputFiles(String inputPath) {
  if (!Directory(inputPath).existsSync() && !File(inputPath).existsSync()) {
    throw CliUsageError('Input not found: "$inputPath".');
  }
  if (!Directory(inputPath).existsSync()) {
    return [inputPath];
  }
  final files = Directory(inputPath)
      .listSync()
      .whereType<File>()
      .where((f) =>
          f.path.toLowerCase().endsWith('.txt') &&
          !f.path.split(Platform.pathSeparator).last.startsWith('.'))
      .map((f) => f.path)
      .toList()
    ..sort();
  if (files.isEmpty) {
    throw CliUsageError('No .txt files found in "$inputPath".');
  }
  return files;
}

/// Renders a voice listing for [model] (or all models when null), including
/// friendly aliases resolved from [config].
String renderVoiceListing({
  TtsModelProfile? model,
  required VoiceConfig config,
}) {
  final profiles = model != null ? [model] : kModelProfiles.values.toList();
  final out = StringBuffer();
  for (final p in profiles) {
    out.writeln();
    out.writeln('${p.alias} — ${p.id} (${p.format})');
    out.writeln('  default voice:  ${p.defaultVoice}');
    final aliases = config.aliases[p.alias] ?? const <String, String>{};
    if (p.voiceFreeForm) {
      out.write('  voices:         free-form provider ids');
      if (aliases.isEmpty) {
        out.writeln();
      } else {
        out.writeln(' (friendly aliases below)');
      }
    } else {
      out.writeln('  voices:         ${p.voices.join(', ')}');
    }
    if (aliases.isNotEmpty) {
      out.writeln('  aliases:        ${aliases.entries.map((e) => '${e.key} → ${e.value}').join(', ')}');
    }
  }
  return out.toString();
}

const usage = '''
Usage: dart run bin/main.dart --input <path> [options]

Required:
  --input <path>            Path to a text file, or a directory of .txt files
                            (top-level, sorted, hidden files skipped) to narrate
                            as a batch.

Options:
  --list-voices [model]     List voices/aliases for a model (optional; default
                            lists all models) and exit. Also honors --model and
                            --config.
  --model <alias|id>        TTS model: gemini (default), kokoro, or fish, or a
                            full model id. Controls voice set, prompt styling,
                            and output format.
  --voice <name>            Model-specific voice. For gemini: one of its 30
                            named voices (default: Charon). For kokoro: a
                            provider voice id such as bf_emma or bm_lewis;
                            any id is accepted (prefix a=_US, b=_British). For
                            fish: a 32-hex fish.audio id (default:
                            89f41ea230034706881f85a8227d6ab9). Friendly
                            aliases from the voice config are resolved to the
                            raw id.
  --accent <text>           Accent description folded into the prompt
                            (gemini only; ignored by kokoro).
  --style <text>            Style/register description in prompt (gemini only;
                            ignored by kokoro).
  --tags on|off             Prepend a [calm] tag (gemini only; default: off).
  --passage-prefix <text>   Pooled preamble applied to each paragraph.
  --min-words <n>           Merge paragraphs shorter than n words into the next
                            (default: 30).
  --sample-len <n>          Narrate only the first n paragraphs.
  --dry-run                 Print the chunk plan + cost estimate and exit
                            (no API call).
  --resume                  Skip chunks whose prompt+fingerprint already exist
                            in the output manifest (re-run safe; no re-billing).
  --out <dir>               Output directory (default: "output/<input>/").
  --config <path>           Voice config JSON (default: ~/.config/tts-narrator/
                            voice_config.json). Friendly voice aliases + api_key.
  --api-key <key>           OpenRouter API key (defaults to api_key in config,
                            then OPENROUTER_API_KEY).

Output goes to <out>/<input-stem>_<nn>.<ext> — gemini writes 24 kHz PCM WAVs,
kokoro and fish write MP3s.
Example:
  dart run bin/main.dart --input /path/to/text.txt --voice Charon --sample-len 1
  dart run bin/main.dart --input /path/to/text.txt --model kokoro --voice Emma
  dart run bin/main.dart --input /path/to/text.txt --model fish
''';