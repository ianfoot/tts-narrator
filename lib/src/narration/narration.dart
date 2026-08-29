import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'config.dart';
import 'prompt.dart';
import 'tts_client.dart';
import 'wav.dart';

/// Max characters per narration chunk. Scenes (blank-line-separated
/// paragraphs) are kept whole; only a scene longer than this cap is split at
/// sentence boundaries. Balances call count vs per-call drift: Google
/// recommends avoiding fragments (short chunks lose voice lock-in) while
/// keeping outputs under a few minutes.
const _maxChunkLength = 4000;

/// Chunks source text into narration units.
///
/// Paragraphs are split on blank lines. A paragraph shorter than
/// [minWords] words is merged into the following paragraph so tiny
/// fragments don't get an isolated reading. Any resulting paragraph longer
/// than [maxChunkLength] chars is further split at sentence boundaries.
/// Returns non-empty, trimmed chunks.
List<String> chunkText(String text, {int minWords = 30}) {
  final raw = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final paragraphs = raw
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  final merged = <String>[];
  final buffer = StringBuffer();
  for (final paragraph in paragraphs) {
    final words = paragraph.split(RegExp(r'\s+')).length;
    if (buffer.isNotEmpty && words < minWords) {
      buffer.write(' $paragraph');
    } else {
      if (buffer.isNotEmpty) {
        merged.add(buffer.toString());
      }
      buffer
        ..clear()
        ..write(paragraph);
    }
  }
  if (buffer.isNotEmpty) {
    merged.add(buffer.toString());
  }

  final chunks = <String>[];
  for (final paragraph in merged) {
    if (paragraph.length <= _maxChunkLength) {
      chunks.add(paragraph);
      continue;
    }
    chunks.addAll(_splitLongParagraph(paragraph));
  }
  return chunks;
}

/// Splits a long paragraph at sentence boundaries, packing sentences into
/// chunks of at most [_maxChunkLength] characters.
List<String> _splitLongParagraph(String paragraph) {
  final sentences = paragraph
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  final chunks = <String>[];
  final buffer = StringBuffer();
  for (final sentence in sentences) {
    final wouldBe = buffer.isEmpty ? sentence : '${buffer.toString()} $sentence';
    if (wouldBe.length <= _maxChunkLength || buffer.isEmpty) {
      buffer
        ..clear()
        ..write(wouldBe);
    } else {
      chunks.add(buffer.toString());
      buffer
        ..clear()
        ..write(sentence);
    }
  }
  if (buffer.isNotEmpty) {
    chunks.add(buffer.toString());
  }
  return chunks;
}

/// Progress callback: [index] 0-based, [total], [paragraph] preview.
typedef NarrationProgress = void Function(
  int index,
  int total,
  String paragraph,
);

/// Reads [config.inputPath] and returns the narration chunk plan
/// (scenes/paragraphs to narrate, after min-word merge and length split).
List<String> planChunks(NarrationConfig config) {
  final source = File(config.inputPath).readAsStringSync();
  final paragraphs = chunkText(source, minWords: config.minWords);
  if (paragraphs.isEmpty) {
    throw StateError('No paragraphs found in "${config.inputPath}".');
  }
  return paragraphs;
}

/// Lowercased, file-friendly slug of the input filename without its extension
/// (e.g. "A Shorts Story Draft 5.txt" -> "a_shorts_story_draft_5").
String inputStem(String inputPath) {
  final name = inputPath.split(Platform.pathSeparator).last;
  final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
  return base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

/// Last path component of an output directory, for append-avoidance.
String outDirBasename(String outDir) =>
    outDir.split(Platform.pathSeparator).last;

/// Final output directory for [config]: the out dir joined with the input
/// stem unless the stem is already the trailing component.
String outputDirPath(NarrationConfig config) {
  final stem = inputStem(config.inputPath);
  return outDirBasename(config.outDir) == stem
      ? config.outDir
      : '${config.outDir}/$stem';
}

/// Narrates [config.inputPath] paragraph by paragraph, writing WAV files and a
/// manifest into [config.outDir].
Future<void> narrate(
  NarrationConfig config, {
  NarrationProgress? onProgress,
}) async {
  final paragraphs = planChunks(config);

  final count = min(config.sampleLen ?? paragraphs.length, paragraphs.length);
  final client = TtsClient(apiKey: config.apiKey);
  final stem = inputStem(config.inputPath);
  final dir = outputDirPath(config);
  final outDir = Directory(dir)..createSync(recursive: true);
  final extension = config.profile.format == 'pcm' ? 'wav' : 'mp3';
  final rate = config.profile.sampleRate;
  final pad = count.toString().length;
  final records = <Map<String, Object?>>[];

  for (var i = 0; i < count; i++) {
    final paragraph = paragraphs[i];
    onProgress?.call(i, count, paragraph);

    // Gemini understands accent/style/tag directives woven into the text;
    // other models would read them aloud, so pass the raw passage instead.
    final input = config.profile.promptStyle
        ? buildPrompt(config, paragraph)
        : paragraph;
    final audio = await client.synthesize(
      model: config.profile.id,
      responseFormat: config.profile.format,
      voice: config.profile.sendsVoiceField ? config.voice : null,
      input: input,
    );

    final baseName = '${stem}_${(i + 1).toString().padLeft(pad, '0')}';
    final audioFile =
        '${outDir.path}${Platform.pathSeparator}$baseName.$extension';
    if (config.profile.format == 'pcm') {
      final bytes = BytesBuilder(copy: false);
      bytes.add(audio);
      writeWav(path: audioFile, bytes: bytes, sampleRate: rate ?? 24000);
    } else {
      File(audioFile).writeAsBytesSync(audio, flush: true);
    }

    final fingerprint = _fingerprint(audio);
    final duration =
        (rate != null && config.profile.format == 'pcm')
            ? audio.length / (rate * 2)
            : null;
    records.add({
      'index': i + 1,
      'wav': '$baseName.$extension',
      'bytes': audio.length,
      'duration_seconds': duration,
      'fingerprint': fingerprint,
      'excerpt': paragraph.length > 120
          ? '${paragraph.substring(0, 120)}…'
          : paragraph,
      'prompt': input,
    });
  }

  final manifest = {
    'model': config.profile.id,
    'voice': config.voice,
    if (config.voiceLabel != null && config.voiceLabel != config.voice)
      'voice_label': config.voiceLabel,
    'format': config.profile.format,
    'sample_rate': ?rate,
    'max_chunk_length': _maxChunkLength,
    // ignore: avoid_redundant_argument_values
    'paragraphs_total': paragraphs.length,
    'paragraphs_narrated': count,
    'paragraphs': records,
  };
  File('${outDir.path}${Platform.pathSeparator}manifest.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
}

/// Lightweight content fingerprint (FNV-1a 64-bit) for manifest bookkeeping.
String _fingerprint(List<int> bytes) {
  var h1 = 0x811c9dc5;
  var h2 = 0x1000193;
  for (final b in bytes) {
    h1 = ((h1 * 0x01000193) ^ b) & 0xFFFFFFFF;
    h2 = ((h2 * 0x01000193) ^ ~b) & 0xFFFFFFFF;
  }
  return '${h1.toRadixString(16).padLeft(8, '0')}'
      '${h2.toRadixString(16).padLeft(8, '0')}';
}