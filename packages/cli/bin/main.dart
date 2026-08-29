import 'dart:io';

import 'package:tts_narrator_core/src/cli/args.dart';
import 'package:tts_narrator_core/src/cli/voice_config.dart';
import 'package:tts_narrator_core/src/narration/config.dart';
import 'package:tts_narrator_core/src/narration/cost.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';
import 'package:tts_narrator_core/src/narration/narration.dart';

Future<int> main(List<String> args) async {
  // --help / --version / --list-voices handled before strict parsing.
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(usage);
    return 0;
  }
  if (args.contains('--list-voices')) {
    return _runListVoices(args);
  }

  NarrationConfig config;
  try {
    config = parseArgs(args);
  } on CliUsageError catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln();
    stderr.writeln(usage);
    return 64; // EX_USAGE
  }

  List<String> inputs;
  try {
    inputs = expandInputFiles(config.inputPath);
  } on CliUsageError catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln();
    stderr.writeln(usage);
    return 64; // EX_USAGE
  }

  stdout.writeln('Model:  ${config.profile.alias} (${config.profile.id})');
  final label = config.voiceLabel != null && config.voiceLabel != config.voice
      ? '${config.voiceLabel} (${config.voice})'
      : config.voice;
  stdout.writeln('Voice:  $label');
  stdout.writeln('Format: ${config.profile.format}');
  stdout.writeln('Input:  ${inputs.length == 1 ? inputs.first : '${inputs.length} files (${config.inputPath})'}');
  stdout.writeln(
    'Tags:   ${config.useCalmTag ? 'on ([calm])' : 'off'}',
  );
  if (config.resume) {
    stdout.writeln('Resume: on (skips chunks matching the existing manifest)');
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
        final chunks = planChunks(fileConfig);
        totalMinutes += estimateMinutes(chunks);
        totalCost += estimateCostUsd(config.profile, chunks);
        final pad = chunks.length.toString().length;
        stdout.writeln('\n== $stem == (${chunks.length} chunk(s))');
        for (var i = 0; i < chunks.length; i++) {
          final words = chunks[i].split(RegExp(r'\s+')).length;
          final preview = chunks[i].length > 70
              ? '${chunks[i].substring(0, 70)}…'
              : chunks[i];
          stdout.writeln('${i + 1}. ($words words) ${preview.split('\n').first}');
        }
        stdout.writeln(
          '  Output: ${outputDirPath(fileConfig)}'
          '${Platform.pathSeparator}${stem}_${'1'.padLeft(pad, '0')}.$extension … '
          '${stem}_${chunks.length.toString().padLeft(pad, '0')}.$extension + manifest.json',
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
    } on Exception catch (e) {
      stderr.writeln('Dry run failed: $e');
      return 1;
    }
    return 0;
  }

  try {
    for (final file in inputs) {
      final fileConfig = config.copyWith(inputPath: file);
      final stem = inputStem(file);
      final chunks = planChunks(fileConfig);
      final estimate = estimateCostUsd(config.profile, chunks);
      final minutes = estimateMinutes(chunks);
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
    }
  } on Exception catch (e) {
    stderr.writeln('Narration failed: $e');
    return 1;
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

  TtsModelProfile? model;
  if (modelArg != null) {
    model = profileFor(modelArg);
    if (model == null) {
      stderr.writeln(
        'Unknown model "$modelArg". Available: ${kModelProfiles.keys.join(', ')}.',
      );
      return 64;
    }
  }

  VoiceConfig voiceConfig = const VoiceConfig();
  try {
    voiceConfig = loadVoiceConfig(configPath ?? defaultConfigPath());
  } on VoiceConfigError catch (e) {
    stderr.writeln('Error: $e');
    return 64;
  }

  stdout.writeln('Voices for ${model?.alias ?? 'all models'}:');
  stdout.write(renderVoiceListing(model: model, config: voiceConfig));
  stdout.writeln();
  return 0;
}