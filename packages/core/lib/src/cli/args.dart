import 'dart:io';

import 'package:args/args.dart';

import '../narration/config.dart';
import '../narration/model_profiles.dart';
import '../narration/tts_provider.dart';
import 'voice_config.dart';

/// Thrown when the user provides invalid CLI arguments.
class InvalidCliArgumentError implements Exception {
  InvalidCliArgumentError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Parses command-line arguments into a [NarrationConfig].
///
/// `--input` is required (no default filenames). Unknown flags and malformed
/// values raise [InvalidCliArgumentError]. Any non-fatal config warnings (e.g. a skipped
/// malformed model file) are appended to [warningsOut] for the caller to
/// surface.
NarrationConfig parseArgs(List<String> args, {List<String>? warningsOut}) {
  final parser = ArgParser()
    ..addOption('input', abbr: 'i', help: 'Path to input file or directory')
    ..addOption('model', abbr: 'm', help: 'TTS model alias or id')
    ..addOption('voice', abbr: 'v', help: 'Voice alias or provider id')
    ..addOption('accent', help: 'Accent description (gemini only; ignored by kokoro)')
    ..addOption('style', help: 'Style/register description in prompt (gemini only)')
    ..addOption('passage-prefix', help: 'Pooled preamble applied to each paragraph')
    ..addOption('out', help: 'Output directory (default: "output")')
    ..addOption('config', help: 'Voice config directory')
    ..addOption('api-key', help: 'Opaque api_key setting for provider')
    ..addOption('provider', help: 'Override the model/provider id')
    ..addOption('sample-len', help: 'Narrate only the first n paragraphs')
    ..addOption('min-words', defaultsTo: '30', help: 'Merge paragraphs shorter than n words')
    ..addFlag('send-whole-file', help: 'Narrate whole file in a single TTS call')
    ..addFlag('dry-run', help: 'Print segment plan + cost estimate and exit')
    ..addFlag('resume', help: 'Skip segments already in output manifest')
    ..addFlag('list-voices', help: 'List voices/aliases for a model and exit')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage information');

  late final ArgResults results;
  try {
    results = parser.parse(args);
  } on ArgParserException catch (e) {
    throw InvalidCliArgumentError(e.message);
  }

  if (results.flag('help')) {
    throw InvalidCliArgumentError(usage);
  }

  // Required --input check.
  final input = results['input'] as String?;
  if (input == null || input.trim().isEmpty) {
    throw InvalidCliArgumentError('--input <path> is required (no default filename).');
  }

  // Numeric parsing for --sample-len and --min-words.
  final sampleLenStr = results['sample-len'] as String?;
  var sampleLen = -1;
  if (sampleLenStr != null && sampleLenStr.isNotEmpty) {
    final n = int.tryParse(sampleLenStr);
    if (n == null || n < 1) {
      throw InvalidCliArgumentError('--sample-len must be a positive integer, got "$sampleLenStr".');
    }
    sampleLen = n;
  }

  final minWordsStr = results['min-words'] as String?;
  var minWords = 30;
  if (minWordsStr != null && minWordsStr.isNotEmpty) {
    final n = int.tryParse(minWordsStr);
    if (n == null || n < 1) {
      throw InvalidCliArgumentError('--min-words must be a positive integer, got "$minWordsStr".');
    }
    minWords = n;
  }

  // Voice and style defaults.
  var voice = results['voice'] as String? ?? '';
  final voiceSpecified = results.wasParsed('voice');
  var accent = results['accent'] as String? ?? 'southern British English, neutral and clear';
  var style = results['style'] as String? ?? 'warm, composed, restrained, literary';
  var prefix = results['passage-prefix'] as String? ??
      'Narrate this passage for an audiobook. You are a warm, composed female narrator.';
  final outDir = results['out'] as String? ?? 'output';
  final dryRun = results.flag('dry-run');
  final resume = results.flag('resume');
  final sendWholeFile = results.flag('send-whole-file');
  final apiKey = results['api-key'] as String?;
  final configPath = results['config'] as String?;
  final providerFlag = results['provider'] as String?;
  final modelArg = results['model'] as String?;

  // Voice config: model wiring, voice aliases, defaults, pricing, providers.
  final cfgDir = configPath ?? defaultConfigDir();
  if (configPath != null && !Directory(cfgDir).existsSync()) {
    throw InvalidCliArgumentError('Voice config directory not found: "$cfgDir".');
  }
  final (VoiceConfig, List<String>) loaded;
  try {
    loaded = loadVoiceConfig(cfgDir);
  } on VoiceConfigurationError catch (e) {
    throw InvalidCliArgumentError('$e');
  }
  final voiceConfig = loaded.$1;
  if (warningsOut != null) warningsOut.addAll(loaded.$2);

  // Model resolution.
  var profile = defaultModelFor(voiceConfig);
  if (modelArg != null) {
    final resolved = profileFor(modelArg, voiceConfig);
    if (resolved == null) {
      final aliases = effectiveModels(voiceConfig)
          .map((p) => p.alias)
          .join(', ');
      throw InvalidCliArgumentError(
        'Unknown model "$modelArg". Available: $aliases '
        '(or pass a full model id).',
      );
    }
    profile = resolved;
  }

  // --provider overrides.
  if (providerFlag != null) {
    try {
      ttsProviderRegistry.resolve(providerFlag);
    } on StateError catch (e) {
      throw InvalidCliArgumentError(e.message);
    }
    profile = profile.copyWith(provider: providerFlag);
  }

  // Voice resolution.
  final String voiceId;
  final String voiceLabel;
  if (voiceSpecified) {
    (voiceId, voiceLabel) = voiceConfig.resolveVoice(profile.alias, voice);
  } else {
    try {
      (voiceId, voiceLabel) = defaultVoiceFor(profile, voiceConfig);
    } on VoiceConfigurationError catch (e) {
      throw InvalidCliArgumentError(e.message);
    }
  }

  // Provider settings.
  final rawSettings = <String, String>{
    ...?voiceConfig.providers[profile.provider],
  };
  if (apiKey != null && apiKey.trim().isNotEmpty) {
    rawSettings['api_key'] = apiKey;
  }
  final Map<String, String> providerSettings;
  if (dryRun) {
    providerSettings = const {};
  } else {
    try {
      providerSettings = resolveSettings(
        rawSettings,
        env: Platform.environment,
      );
    } on StateError catch (e) {
      throw InvalidCliArgumentError(e.message);
    }
  }

  return NarrationConfig(
    inputPath: input,
    profile: profile,
    voice: voiceId,
    voiceLabel: voiceId == voiceLabel ? null : voiceLabel,
    accent: accent,
    style: style,
    passagePrefix: prefix,
    minWords: minWords,
    sendWholeFile: sendWholeFile,
    sampleLen: sampleLen > 0 ? sampleLen : null,
    outDir: outDir,
    dryRun: dryRun,
    resume: resume,
    pricing: voiceConfig.pricingFor(profile.alias),
    providerSettings: providerSettings,
  );
}

/// Expands a single `--input` value into one or more `.txt` files to narrate.
///
/// A regular file yields itself. A directory yields its top-level `*.txt`
/// files, sorted and excluding hidden files. Throws a [InvalidCliArgumentError] when the
/// path is missing or yields no files.
List<String> expandInputFiles(String inputPath) {
  if (!Directory(inputPath).existsSync() && !File(inputPath).existsSync()) {
    throw InvalidCliArgumentError('Input not found: "$inputPath".');
  }
  if (!Directory(inputPath).existsSync()) {
    return [inputPath];
  }
  final files =
      Directory(inputPath)
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.toLowerCase().endsWith('.txt') &&
                !f.path.split(Platform.pathSeparator).last.startsWith('.'),
          )
          .map((f) => f.path)
          .toList()
        ..sort();
  if (files.isEmpty) {
    throw InvalidCliArgumentError('No .txt files found in "$inputPath".');
  }
  return files;
}

/// Renders a voice listing for [model] (or all models when null), including
/// the configured default and friendly aliases from [config].
String renderVoiceListing({
  TtsModelProfile? model,
  required VoiceConfig config,
}) {
  final profiles = model != null ? [model] : effectiveModels(config);
  final out = StringBuffer();
  for (final p in profiles) {
    out.writeln();
    out.writeln('${p.alias} — ${p.id} (${p.format})');
    try {
      final (id, label) = defaultVoiceFor(p, config);
      final shown = id == label ? label : '$label ($id)';
      out.writeln('  default voice:  $shown');
    } on VoiceConfigurationError {
      out.writeln('  default voice:  none configured');
    }
    final voices = config.voices[p.alias] ?? const <String, Voice>{};
    if (voices.isNotEmpty) {
      final shown = voices.entries
          .map((e) {
            final g = e.value.gender;
            final tag = g == null ? '' : ' [${g.shorthand}]';
            return '${e.key} → ${e.value.id}$tag';
          })
          .join(', ');
      out.writeln('  aliases:        $shown');
    } else {
      out.writeln(
        '  voices:         none configured — add "${p.alias}" aliases in the '
        'voice config',
      );
    }
  }
  return out.toString();
}

const usage = '''
Usage: tts-narrator --input <path> [options]

Required:
  --input <path>            Path to a text file, or a directory of .txt files
                            (top-level, sorted, hidden files skipped) to narrate
                            as a batch.

Options:
  --list-voices [model]     List voices/aliases for a model (optional; default
                            lists all models) and exit. Also honors --model and
                            --config.
  --model <alias|id>        TTS model: fish (default, free), gemini, or kokoro,
                            or a full model id. Controls prompt styling and
                            output format.
  --provider <id>           Override the provider serving the model. Unknown
                            ids list the registered providers.
  --voice <name>            Voice: a friendly alias or a raw provider id.
                            Accepts any value (no validation) so you can test
                            voices. Defaults to the config "defaults" entry, or
                            fish's free "British Female Narrator" when none.
  --accent <text>           Accent description folded into the prompt
                            (gemini only; ignored by kokoro).
  --style <text>            Style/register description in prompt (gemini only;
                            ignored by kokoro).
  --passage-prefix <text>   Pooled preamble applied to each paragraph. Add
  --min-words <n>           Merge paragraphs shorter than n words into the next
                            (default: 30).
  --send-whole-file         Narrate the whole file in a single TTS call instead
                            of segmenting it (--min-words is ignored; capped at
                            60,000 characters).
  --sample-len <n>          Narrate only the first n paragraphs.
  --dry-run                 Print the segment plan + cost estimate and exit
                            (no API call).
  --resume                  Skip segments whose prompt+fingerprint already exist
                            in the output manifest (re-run safe; no re-billing).
  --out <dir>               Output directory (default: "output/<input>/").
  --config <path>           Voice config directory (default: ~/.config/tts-
                            narrator/). Holds config.json (default model +
                            providers) + one <alias>.json per model (provider,
                            aliases, defaults, pricing).
  --api-key <key>           Opaque "api_key" setting merged into the selected
                            provider's settings (overrides the config).

Output goes to <out>/<input-stem>_<nn>.<ext> — gemini writes 24 kHz PCM WAVs,
kokoro and fish write MP3s.
Example:
  tts-narrator --input /path/to/text.txt --voice Charon --sample-len 1
  tts-narrator --input /path/to/text.txt --model kokoro --voice Emma
  tts-narrator --input /path/to/text.txt --model fish
(From source: cd packages/cli && fvm dart run bin/main.dart -- ...)
''';
