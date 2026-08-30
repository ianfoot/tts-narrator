import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'abort.dart';
import 'config.dart';
import 'prompt.dart';
import 'tts_provider.dart';
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
    final wouldBe = buffer.isEmpty
        ? sentence
        : '${buffer.toString()} $sentence';
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
  String paragraph, {
  bool resumed,
});

/// Completion callback: called once each chunk's audio file is on disk,
/// with the 0-based [index] and the absolute [filePath] of the written clip
/// (including resumed chunks). Lets a GUI enable per-chunk playback as soon
/// as a chunk lands, rather than waiting for the whole run.
typedef NarrationChunkComplete = void Function(
  int index,
  String filePath, {
  bool resumed,
});

/// Reads [config]'s source text: the in-memory [NarrationConfig.sourceText]
/// when set, else the file at [NarrationConfig.inputPath].
String _sourceText(NarrationConfig config) => config.sourceText ??
    File(config.inputPath).readAsStringSync();

/// Returns the narration chunk plan (scenes/paragraphs to narrate, after
/// min-word merge and length split) for [config], reading from
/// [NarrationConfig.sourceText] or the file at [config.inputPath].
List<String> planChunks(NarrationConfig config) {
  final source = _sourceText(config);
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
  final base = name.contains('.')
      ? name.substring(0, name.lastIndexOf('.'))
      : name;
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

/// Narrates [config] paragraph by paragraph (reading [NarrationConfig.sourceText]
/// when set, else the file at [config.inputPath]), writing WAV files and a
/// manifest into [config.outDir]. The manifest is rewritten after every chunk
/// so a failed run can be resumed via `--resume`.
///
/// [abort], when given, is checked before each chunk and thread through to the
/// HTTP client; cancelling it throws [AbortException] and stops the run.
Future<void> narrate(
  NarrationConfig config, {
  NarrationProgress? onProgress,
  NarrationChunkComplete? onChunkComplete,
  AbortToken? abort,
}) async {
  final paragraphs = planChunks(config);

  final count = min(config.sampleLen ?? paragraphs.length, paragraphs.length);
  final provider = ttsProviderRegistry.resolve(config.profile.provider);
  final stem = inputStem(config.inputPath);
  final dir = outputDirPath(config);
  final outDir = Directory(dir)..createSync(recursive: true);
  final extension = config.profile.format == 'pcm' ? 'wav' : 'mp3';
  final rate = config.profile.sampleRate;
  final records = <Map<String, Object?>>[];

  final existing = config.resume
      ? readManifestRecords(outDir)
      : const <Map<String, Object?>>[];

  for (var i = 0; i < count; i++) {
    abort?.throwIfCancelled();
    final paragraph = paragraphs[i];
    final index = i + 1;

    // Gemini understands accent/style/tag directives woven into the text;
    // other models would read them aloud, so pass the raw passage instead.
    final input = config.profile.promptStyle
        ? buildPrompt(config, paragraph)
        : paragraph;

    final padWidth = count.toString().length;
    final baseName = '${stem}_${index.toString().padLeft(padWidth, '0')}';
    final audioFile =
        '${outDir.path}${Platform.pathSeparator}$baseName.$extension';

    // Resume: reuse an identical prior chunk (same index + prompt + file) and
    // carry its fingerprint/bytes across, so a re-run doesn't re-bill it.
    final prior = resumeMatch(existing, index, input, dir);
    if (prior != null) {
      records.add(prior);
      onProgress?.call(i, count, paragraph, resumed: true);
      onChunkComplete?.call(
        i,
        '$dir${Platform.pathSeparator}${prior['wav']}',
        resumed: true,
      );
      _writeManifest(outDir, config, records, paragraphs.length, count, rate);
      continue;
    }

    onProgress?.call(i, count, paragraph);
    final audio = await provider.synthesize(
      model: config.profile.id,
      voice: config.profile.sendsVoiceField ? config.voice : null,
      responseFormat: config.profile.format,
      settings: config.providerSettings,
      input: input,
      abort: abort,
    );

    if (config.profile.format == 'pcm') {
      final bytes = BytesBuilder(copy: false);
      bytes.add(audio.bytes);
      writeWav(path: audioFile, bytes: bytes, sampleRate: rate ?? 24000);
    } else {
      File(audioFile).writeAsBytesSync(audio.bytes, flush: true);
    }

    final fingerprint = fingerprintOf(audio.bytes);
    final duration = (rate != null && config.profile.format == 'pcm')
        ? audio.bytes.length / (rate * 2)
        : null;
    records.add({
      'index': index,
      'wav': '$baseName.$extension',
      'bytes': audio.bytes.length,
      'duration_seconds': duration,
      'fingerprint': fingerprint,
      'excerpt': paragraph.length > 120
          ? '${paragraph.substring(0, 120)}…'
          : paragraph,
      'prompt': input,
    });
    onChunkComplete?.call(i, audioFile);
    _writeManifest(outDir, config, records, paragraphs.length, count, rate);
  }

  _writeManifest(outDir, config, records, paragraphs.length, count, rate);
}

/// Returns the prior record for [index] from [existing] when `--resume` can
/// reuse it: same index, same [input] prompt, and the audio file still exists.
Map<String, Object?>? resumeMatch(
  List<Map<String, Object?>> existing,
  int index,
  String input,
  String dir,
) {
  for (final r in existing) {
    if (r['index'] == index && r['prompt'] == input) {
      final wav = r['wav'];
      if (wav is String &&
          File('$dir${Platform.pathSeparator}$wav').existsSync()) {
        return r;
      }
    }
  }
  return null;
}

/// Loads per-chunk records from a prior run's manifest, or empty when none.
List<Map<String, Object?>> readManifestRecords(Directory outDir) {
  final manifestFile = File(
    '${outDir.path}${Platform.pathSeparator}manifest.json',
  );
  if (!manifestFile.existsSync()) return const [];
  try {
    final raw = jsonDecode(manifestFile.readAsStringSync());
    final paragraphs = (raw as Map<String, dynamic>)['paragraphs'];
    if (paragraphs is List) {
      return paragraphs
          .whereType<Map<String, dynamic>>()
          .cast<Map<String, Object?>>()
          .toList();
    }
  } on Exception {
    // Unreadable/stale manifest is not fatal — resume simply re-narrates.
  }
  return const [];
}

void _writeManifest(
  Directory outDir,
  NarrationConfig config,
  List<Map<String, Object?>> records,
  int paragraphsTotal,
  int count,
  int? rate,
) {
  final manifest = {
    'model': config.profile.id,
    'voice': config.voice,
    if (config.voiceLabel != null && config.voiceLabel != config.voice)
      'voice_label': config.voiceLabel,
    'format': config.profile.format,
    'sample_rate': ?rate,
    'max_chunk_length': _maxChunkLength,
    // ignore: avoid_redundant_argument_values
    'paragraphs_total': paragraphsTotal,
    'paragraphs_narrated': records.length,
    'paragraphs': records,
  };
  File('${outDir.path}${Platform.pathSeparator}manifest.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
}

/// Lightweight content fingerprint (FNV-1a 64-bit) for manifest bookkeeping.
String fingerprintOf(List<int> bytes) {
  var h1 = 0x811c9dc5;
  var h2 = 0x1000193;
  for (final b in bytes) {
    h1 = ((h1 * 0x01000193) ^ b) & 0xFFFFFFFF;
    h2 = ((h2 * 0x01000193) ^ ~b) & 0xFFFFFFFF;
  }
  return '${h1.toRadixString(16).padLeft(8, '0')}'
      '${h2.toRadixString(16).padLeft(8, '0')}';
}
