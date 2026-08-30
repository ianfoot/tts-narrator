import 'dart:io';

import '../narration/config.dart';
import '../narration/model_profiles.dart';
import '../narration/tts_provider.dart';
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
  String? modelArg;
  var voice = '';
  var voiceSpecified = false;
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
  String? providerFlag;

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
        modelArg = take(arg);
      case '--voice':
        voice = take(arg);
        voiceSpecified = true;
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
      case '--provider':
        providerFlag = take(arg);
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

  // Voice config: model wiring, voice aliases, defaults, pricing, providers.
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

  // Model resolution: default is the fish bootstrap (overridable via config
  // "models"); an explicit --model resolves against the effective model set.
  var profile = kDefaultProfile.profile;
  if (modelArg != null) {
    final resolved = profileFor(modelArg, voiceConfig);
    if (resolved == null) {
      final aliases = effectiveModels(voiceConfig).map((p) => p.alias).join(', ');
      throw CliUsageError(
        'Unknown model "$modelArg". Available: $aliases '
        '(or pass a full model id).',
      );
    }
    profile = resolved;
  }

  // --provider overrides the model's/default provider; unknown ids error with
  // the registered list (via the registry's message).
  if (providerFlag != null) {
    try {
      ttsProviderRegistry.resolve(providerFlag);
    } on StateError catch (e) {
      throw CliUsageError(e.message);
    }
    profile = profile.copyWith(provider: providerFlag);
  }

  // Voice resolution. An explicit --voice passes straight through (no
  // validation — providers add/remove voices and testing arbitrary ids is a
  // feature); otherwise the config default is used, with fish falling back to
  // its compiled free default on cold start.
  final String voiceId;
  final String voiceLabel;
  if (voiceSpecified) {
    (voiceId, voiceLabel) = voiceConfig.resolveVoice(profile.alias, voice);
  } else {
    try {
      (voiceId, voiceLabel) = defaultVoiceFor(profile, voiceConfig);
    } on VoiceConfigError catch (e) {
      throw CliUsageError(e.message);
    }
  }

  // Provider settings: the selected provider's block from the config, with
  // --api-key merged in as the generic `api_key` setting (it wins over any
  // `providers.<id>.api_key`). `${ENV}` refs are resolved once at build time;
  // no env reads happen per chunk.
  final rawSettings = <String, String>{
    ...?voiceConfig.providers[profile.provider],
  };
  if (apiKey != null && apiKey.trim().isNotEmpty) {
    rawSettings['api_key'] = apiKey;
  }
  final providerSettings =
      resolveSettings(rawSettings, env: Platform.environment);

  return NarrationConfig(
    inputPath: input,
    profile: profile,
    voice: voiceId,
    voiceLabel: voiceId == voiceLabel ? null : voiceLabel,
    accent: accent,
    style: style,
    useCalmTag: tags,
    passagePrefix: prefix,
    minWords: minWords,
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
    } on VoiceConfigError {
      out.writeln('  default voice:  none configured');
    }
    final aliases = config.aliases[p.alias] ?? const <String, String>{};
    if (aliases.isNotEmpty) {
      out.writeln(
        '  aliases:        '
        '${aliases.entries.map((e) => '${e.key} → ${e.value}').join(', ')}',
      );
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
                            voice_config.json). Holds voice aliases, defaults,
                            pricing, and the per-provider settings block.
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