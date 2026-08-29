import 'dart:io';

import 'package:gemini_tts_narrator/src/cli/args.dart';
import 'package:gemini_tts_narrator/src/narration/config.dart';
import 'package:gemini_tts_narrator/src/narration/narration.dart';

Future<int> main(List<String> args) async {
  // --help / --version handled before strict parsing.
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(usage);
    return 0;
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

  stdout.writeln('Voice:  ${config.voice}');
  stdout.writeln('Input:  ${config.inputPath}');
  stdout.writeln(
    'Tags:   ${config.useCalmTag ? 'on ([calm])' : 'off'}',
  );

  if (config.dryRun) {
    try {
      final chunks = planChunks(config);
      stdout.writeln('Dry run — ${chunks.length} chunk(s) planned:\n');
      for (var i = 0; i < chunks.length; i++) {
        final words = chunks[i].split(RegExp(r'\s+')).length;
        final preview = chunks[i].length > 70
            ? '${chunks[i].substring(0, 70)}…'
            : chunks[i];
        stdout.writeln('${i + 1}. ($words words) ${preview.split('\n').first}');
      }
    } on Exception catch (e) {
      stderr.writeln('Dry run failed: $e');
      return 1;
    }
    return 0;
  }

  try {
    await narrate(
      config,
      onProgress: (index, total, paragraph) {
        final preview = paragraph.length > 60
            ? '${paragraph.substring(0, 60)}…'
            : paragraph;
        stdout.writeln(
          '[${index + 1}/$total] ${preview.split('\n').first}',
        );
      },
    );
  } on Exception catch (e) {
    stderr.writeln('Narration failed: $e');
    return 1;
  }

  stdout.writeln();
  stdout.writeln('Done. WAVs + manifest.json written to ${config.outDir}/.');
  return 0;
}