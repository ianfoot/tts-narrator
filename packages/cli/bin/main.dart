import 'dart:io';

import 'package:tts_narrator_core/tts_narrator_core.dart';
import 'package:tts_narrator_openrouter/openrouter_tts_provider.dart';

/// sysexits.h `EX_USAGE` (64): bad command-line usage.
const _exitUsage = 64;

/// Generic operational failure (dry-run or narration threw).
const _exitFailure = 1;

Future<int> main(List<String> args) async {
  ttsProviderRegistry.register('openrouter', OpenRouterTtsProvider.new);

  // --help / --version / --list-voices handled before strict parsing.
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(usage);
    return 0;
  }
  if (args.contains('--list-voices')) {
    return _runListVoices(args);
  }

  NarrationConfig config;
  final warnings = <String>[];
  try {
    config = parseArgs(args, warningsOut: warnings);
  } on CliUsageError catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln();
    stderr.writeln(usage);
    exitCode = _exitUsage;
    return _exitUsage;
  }

  for (final w in warnings) {
    stderr.writeln('Warning: $w');
  }

  List<String> inputs;
  try {
    inputs = expandInputFiles(config.inputPath);
  } on CliUsageError catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln();
    stderr.writeln(usage);
    exitCode = _exitUsage;
    return _exitUsage;
  }

  stdout.writeln('Model:  ${config.profile.alias} (${config.profile.id})');
  final label = config.voiceLabel != null && config.voiceLabel != config.voice
      ? '${config.voiceLabel} (${config.voice})'
      : config.voice;
  stdout.writeln('Voice:  $label');
  stdout.writeln('Provider: ${config.profile.provider}');
  stdout.writeln('Format: ${config.profile.format}');
  stdout.writeln(
    'Input:  ${inputs.length == 1 ? inputs.first : '${inputs.length} files (${config.inputPath})'}',
  );
  stdout.writeln('Tags:   ${config.useCalmTag ? 'on ([calm])' : 'off'}');
  stdout.writeln(
    'Mode:   ${config.sendWholeFile ? 'whole file (single call)' : 'segmented'}',
  );
  if (config.resume) {
    stdout.writeln(
      'Resume: on (skips segments matching the existing manifest)',
    );
  }
  if (!config.profile.promptStyle &&
      (config.accent.trim().isNotEmpty ||
          config.style.trim().isNotEmpty ||
          config.useCalmTag)) {
    stdout.writeln();
    stdout.writeln(
      'Note: ${config.profile.alias} does not support prompt styling — '
      '--accent/--style/--tags are ignored.',
    );
  }

  final extension = config.profile.format == 'pcm' ? 'wav' : 'mp3';
  final kind = config.profile.format == 'pcm' ? 'WAVs' : 'MP3s';

  if (config.dryRun) {
    try {
      var totalMinutes = 0.0;
      var totalCost = 0.0;
      for (final file in inputs) {
        final fileConfig = config.copyWith(inputPath: file);
        final stem = inputStem(file);
        final segments = planSegments(fileConfig);
        totalMinutes += estimateMinutes(segments);
        totalCost += estimateCostUsd(config.pricing, segments);
        final pad = segments.length.toString().length;
        stdout.writeln('\n== $stem == (${segments.length} segment(s))');
        for (var i = 0; i < segments.length; i++) {
          final words = segments[i].split(RegExp(r'\s+')).length;
          final preview = segments[i].length > 70
              ? '${segments[i].substring(0, 70)}…'
              : segments[i];
          stdout.writeln(
            '${i + 1}. ($words words) ${preview.split('\n').first}',
          );
        }
        stdout.writeln(
          '  Output: ${outputDirPath(fileConfig)}'
          '${Platform.pathSeparator}${stem}_${'1'.padLeft(pad, '0')}.$extension … '
          '${stem}_${segments.length.toString().padLeft(pad, '0')}.$extension + manifest.json',
        );
      }
      if (inputs.length > 1) {
        stdout.writeln('\nBatch total: ${inputs.length} file(s).');
      }
      stdout.writeln(
        'Estimated duration: ${totalMinutes.toStringAsFixed(1)} min '
        '(~${(totalMinutes * 60).round()} s). '
        'Estimated cost: ${formatCostUsd(totalCost)}.',
      );
    } on StateError catch (e) {
      stderr.writeln('Dry run failed: $e');
      exitCode = _exitUsage;
      return _exitUsage;
    } on Exception catch (e) {
      stderr.writeln('Dry run failed: $e');
      exitCode = _exitFailure;
      return _exitFailure;
    }
    return 0;
  }

  try {
    for (final file in inputs) {
      final fileConfig = config.copyWith(inputPath: file);
      final stem = inputStem(file);
      final segments = planSegments(fileConfig);
      final estimate = estimateCostUsd(config.pricing, segments);
      final minutes = estimateMinutes(segments);
      stdout.writeln('\n== $stem ==');
      stdout.writeln(
        '  Estimated duration: ${minutes.toStringAsFixed(1)} min. '
        'Estimated cost: ${formatCostUsd(estimate)}.',
      );
      await narrate(
        fileConfig,
        onProgress: (index, total, paragraph, {bool resumed = false}) {
          final preview = paragraph.length > 60
              ? '${paragraph.substring(0, 60)}…'
              : paragraph;
          stdout.writeln(
            '  [${index + 1}/$total]${resumed ? ' (resumed)' : ''} '
            '${preview.split('\n').first}',
          );
        },
      );
      stdout.writeln(
        '  Done. $kind + manifest.json written to ${outputDirPath(fileConfig)}/.',
      );
      stdout.writeln(
        '  Combined track: '
        '${outputDirPath(fileConfig)}${Platform.pathSeparator}'
        '${stem}_full.${fileConfig.profile.format == 'pcm' ? 'wav' : 'mp3'}',
      );
    }
  } on StateError catch (e) {
    stderr.writeln('Narration failed: $e');
    exitCode = _exitUsage;
    return _exitUsage;
  } on Exception catch (e) {
    stderr.writeln('Narration failed: $e');
    exitCode = _exitFailure;
    return _exitFailure;
  }

  stdout.writeln();
  if (inputs.length > 1) {
    stdout.writeln('Batch complete: ${inputs.length} file(s) narrated.');
  }
  return 0;
}

/// Handles `--list-voices [model]`. Picks any explicit model token, `--model`,
/// and loads friendly aliases via `--config` (or the default config).
int _runListVoices(List<String> args) {
  String? modelArg;
  final li = args.indexOf('--list-voices');
  if (li + 1 < args.length && !args[li + 1].startsWith('-')) {
    modelArg = args[li + 1];
  }
  final mi = args.indexOf('--model');
  if (mi >= 0 && mi + 1 < args.length) {
    modelArg = args[mi + 1];
  }

  String? configPath;
  final ci = args.indexOf('--config');
  if (ci >= 0 && ci + 1 < args.length) {
    configPath = args[ci + 1];
  }

  VoiceConfig voiceConfig;
  final listWarnings = <String>[];
  try {
    final (cfg, warnings) = loadVoiceConfig(configPath ?? defaultConfigDir());
    voiceConfig = cfg;
    listWarnings.addAll(warnings);
  } on VoiceConfigError catch (e) {
    stderr.writeln('Error: $e');
    exitCode = _exitUsage;
    return _exitUsage;
  }
  for (final w in listWarnings) {
    stderr.writeln('Warning: $w');
  }

  TtsModelProfile? model;
  if (modelArg != null) {
    model = profileFor(modelArg, voiceConfig);
    if (model == null) {
      stderr.writeln(
        'Unknown model "$modelArg". Available: '
        '${effectiveModels(voiceConfig).map((p) => p.alias).join(', ')}.',
      );
      exitCode = _exitUsage;
      return _exitUsage;
    }
  }

  stdout.writeln('Voices for ${model?.alias ?? 'all models'}:');
  stdout.write(renderVoiceListing(model: model, config: voiceConfig));
  stdout.writeln();
  return 0;
}
