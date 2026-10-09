import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../config/provider_settings.dart';
import 'abort.dart';
import 'concat.dart';
import 'config.dart';
import 'audio_format.dart';
import 'manifest.dart';
import 'prompt.dart';
import 'speech_client.dart';
import 'wav.dart';

/// Max characters per narration segment. Scenes (blank-line-separated
/// paragraphs) are kept whole; only a longer scene is split at sentence
/// boundaries. Short segments lose voice lock-in, per Google's guidance.
const _maxSegmentLength = 1500;

/// Max characters for a single whole-file narration call
/// ([NarrationConfig.sendWholeFile]). Providers cap payload sizes and time out
/// mid-run, so the GUI hides the "Send whole file" toggle above this size and
/// [planSegments] rejects the plan outright.
const maxWholeFileLength = 60000;

/// Segments source text into narration units.
///
/// Paragraphs are split on blank lines. A paragraph shorter than [minWords]
/// words is merged forward so tiny fragments don't get an isolated reading; a
/// trailing fragment with no following paragraph is kept as-is. Any resulting
/// paragraph longer than [_maxSegmentLength] chars is further split at sentence
/// boundaries. Returns non-empty, trimmed segments.
List<String> segmentText(String text, {int minWords = 30}) {
  final raw = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final paragraphs = raw
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  final merged = <String>[];
  final buffer = StringBuffer();
  var bufferWords = 0;
  for (final paragraph in paragraphs) {
    final words = paragraph.split(RegExp(r'\s+')).length;
    if (buffer.isNotEmpty && (bufferWords < minWords || words < minWords)) {
      buffer.write(' $paragraph');
      bufferWords += words;
    } else {
      if (buffer.isNotEmpty) {
        merged.add(buffer.toString());
      }
      buffer
        ..clear()
        ..write(paragraph);
      bufferWords = words;
    }
  }
  if (buffer.isNotEmpty) {
    merged.add(buffer.toString());
  }

  final segments = <String>[];
  for (final paragraph in merged) {
    if (paragraph.length <= _maxSegmentLength) {
      segments.add(paragraph);
      continue;
    }
    segments.addAll(_splitLongParagraph(paragraph));
  }
  return segments;
}

/// Splits a long paragraph at sentence boundaries, packing sentences into
/// segments of at most [_maxSegmentLength] characters.
List<String> _splitLongParagraph(String paragraph) {
  final sentences = paragraph
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  final segments = <String>[];
  final buffer = StringBuffer();
  for (final sentence in sentences) {
    final wouldBe = buffer.isEmpty
        ? sentence
        : '${buffer.toString()} $sentence';
    if (wouldBe.length <= _maxSegmentLength || buffer.isEmpty) {
      buffer
        ..clear()
        ..write(wouldBe);
    } else {
      segments.add(buffer.toString());
      buffer
        ..clear()
        ..write(sentence);
    }
  }
  if (buffer.isNotEmpty) {
    segments.add(buffer.toString());
  }
  return segments;
}

/// Progress callback: [index] 0-based, [total], [paragraph] preview.
typedef NarrationProgress = void Function(
  int index,
  int total,
  String paragraph, {
  bool resumed,
});

/// Completion callback: called once each segment's audio file is on disk, with
/// the 0-based [index] and the absolute [filePath] of the written clip (including
/// resumed segments). Lets a GUI enable per-segment playback as each one lands.
typedef NarrationSegmentComplete = void Function(
  int index,
  String filePath, {
  bool resumed,
});

/// Reads [config]'s source text: the in-memory [NarrationConfig.sourceText]
/// when set, else the file at [NarrationConfig.inputPath].
String _sourceText(NarrationConfig config) =>
    config.sourceText ?? File(config.inputPath).readAsStringSync();

/// Returns the narration segment plan (scenes/paragraphs to narrate, after
/// min-word merge and length split) for [config], reading from
/// [NarrationConfig.sourceText] or the file at [config.inputPath]. When
/// [NarrationConfig.sendWholeFile] is set, the entire source is returned as a
/// single segment instead of being segmented.
List<String> planSegments(NarrationConfig config) {
  final source = _sourceText(config);
  if (config.sendWholeFile) {
    final whole = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (whole.isEmpty) {
      throw StateError('No paragraphs found in "${config.inputPath}".');
    }
    if (whole.length > maxWholeFileLength) {
      throw StateError(
        'Document is ${whole.length} characters; whole-file narration is '
        'limited to $maxWholeFileLength characters. Turn off "Send whole '
        'file" to narrate it as segments.',
      );
    }
    return [whole];
  }
  final paragraphs = segmentText(source, minWords: config.minWords);
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

/// Resolves the directory a run writes into, from the chosen output folder and
/// the input file name.
///
/// With [nestUnderInputName] (the default, and what
/// [NarrationConfig.nestOutputInInputSubdir] selects) the input stem is appended
/// so several documents narrated into one folder stay separate — unless it is
/// already the trailing component. With [inputPath] null or nesting off, [outDir]
/// is returned untouched.
///
/// Pure, so a GUI can display where a run will land without assembling a whole
/// [NarrationConfig] (which requires a model and a voice).
String resolveOutputDir({
  required String outDir,
  String? inputPath,
  bool nestUnderInputName = true,
}) {
  if (!nestUnderInputName || inputPath == null) return outDir;
  final stem = inputStem(inputPath);
  return outDirBasename(outDir) == stem ? outDir : '$outDir/$stem';
}

/// Final output directory for [config]: the out dir joined with the input
/// stem unless the stem is already the trailing component, or unless the config
/// narrates an in-memory document ([NarrationConfig.nestOutputInInputSubdir] is
/// false), in which case [NarrationConfig.outDir] is used as-is.
String outputDirPath(NarrationConfig config) => resolveOutputDir(
  outDir: config.outDir,
  inputPath: config.inputPath,
  nestUnderInputName: config.nestOutputInInputSubdir,
);

/// Narrates [config] paragraph by paragraph (reading [NarrationConfig.sourceText]
/// when set, else the file at [config.inputPath]), writing WAV files and a
/// manifest into [outputDirPath]. The manifest is rewritten after every segment
/// so a failed run can be resumed via `--resume`.
///
/// [client] is the speech seam, injected by the entrypoint rather than resolved
/// from a registry: core never constructs one. [OpenAiSpeechClient] is the one
/// the app supplies, configured from [NarrationConfig.providerSettings] plus the
/// [NarrationConfig.apiKey] the caller resolved.
///
/// [abort], when given, is checked before each segment and threaded through to
/// the HTTP client; cancelling it throws [AbortException] and stops the run.
Future<void> narrate(
  NarrationConfig config, {
  required SpeechClient client,
  NarrationProgress? onProgress,
  NarrationSegmentComplete? onSegmentComplete,
  AbortToken? abort,
}) async {
  // Fail on an unusable provider block before any work happens. The client
  // raises the same error, but only on segment 1 and after the output directory
  // exists; naming the block here tells the user which connection to fix.
  if (providerBaseUrl(config.providerSettings) == null) {
    throw StateError(
      'TTS provider "${config.profile.provider}" is missing required setting '
      '"base_url" (the speech endpoint root, e.g. '
      '"https://vendor.example/api/v1").',
    );
  }

  final paragraphs = planSegments(config);

  final count = min(config.sampleLen ?? paragraphs.length, paragraphs.length);
  final stem = inputStem(config.inputPath);
  final dir = outputDirPath(config);
  final outDir = Directory(dir)..createSync(recursive: true);
  final extension = config.outputFormat.extension;
  final records = <Map<String, Object?>>[];

  final existing = config.resume
      ? paragraphRecords(outDir)
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

    // Reuse an identical prior segment (same index + prompt + format + file),
    // carrying its record across so a re-run doesn't re-bill it.
    final prior = resumeMatch(existing, index, input, dir, extension);
    if (prior != null) {
      records.add(prior);
      onProgress?.call(i, count, paragraph, resumed: true);
      onSegmentComplete?.call(
        i,
        '$dir${Platform.pathSeparator}${prior['wav']}',
        resumed: true,
      );
      _writeManifest(outDir, config, records, paragraphs.length, count);
      continue;
    }

    onProgress?.call(i, count, paragraph);
    final audio = await client(
      model: config.profile.id,
      voice: config.profile.sendsVoiceField ? config.voice : null,
      responseFormat: config.outputFormat,
      wavResponseFormat: config.profile.wavResponseFormat,
      settings: config.providerSettings,
      apiKey: config.apiKey,
      input: input,
      speed: config.profile.supportsSpeed ? config.speed : null,
      language: config.profile.sendsLanguageField ? config.language : null,
      // Voice design: the model reads the prose instead of a voice id. Falls
      // back to the profile's default so a model that declares the capability
      // never sends an undescribed request the vendor cannot fulfil.
      instruct: config.profile.sendsInstructField
          ? (config.instruct ?? config.profile.defaultInstruct)
          : null,
      abort: abort,
    );

    // Every format arrives as a finished container except a wav run against a
    // model serving headerless samples, where the app writes the missing header.
    final bytes = _asWav(config, audio);
    File(audioFile).writeAsBytesSync(bytes, flush: true);

    records.add({
      'index': index,
      'wav': '$baseName.$extension',
      'bytes': bytes.length,
      'excerpt': paragraph.length > 120
          ? '${paragraph.substring(0, 120)}…'
          : paragraph,
      'prompt': input,
    });
    onSegmentComplete?.call(i, audioFile);
    _writeManifest(outDir, config, records, paragraphs.length, count);
  }

  // Every successful run leaves a combined track next to the segments (same
  // stem, `_full` suffix). Segments stay on disk by default; the GUI's
  // "Clean Up Segments…" removes them afterwards.
  final segmentPaths = [
    for (final r in records)
      '${outDir.path}${Platform.pathSeparator}${r['wav']}',
  ];
  final combinedFile = '${stem}_full.$extension';
  final combinedBytes = File(
    concatSegments(
      segmentPaths,
      outputPath: '${outDir.path}${Platform.pathSeparator}$combinedFile',
      format: config.outputFormat,
    ),
  ).lengthSync();

  _writeManifest(
    outDir,
    config,
    records,
    paragraphs.length,
    count,
    combinedFile: combinedFile,
    combinedBytes: combinedBytes,
  );
}

/// Returns the prior record for [index] from [existing] when `--resume` can
/// reuse it: same index, same [input] prompt, the audio file still exists, and
/// it is in [extension].
///
/// The format check is load-bearing rather than cosmetic. The combined track is
/// assembled from the recorded filenames using the *current* output format, so
/// reusing segments written in the other format either yields an unplayable
/// header-then-MP3 file or throws after the run has already been billed.
/// Refusing the match makes a format switch re-narrate instead, which costs
/// money but never produces a broken file.
Map<String, Object?>? resumeMatch(
  List<Map<String, Object?>> existing,
  int index,
  String input,
  String dir,
  String extension,
) {
  for (final r in existing) {
    if (r['index'] == index && r['prompt'] == input) {
      final wav = r['wav'];
      if (wav is String &&
          _extensionOf(wav) == extension &&
          File('$dir${Platform.pathSeparator}$wav').existsSync()) {
        return r;
      }
    }
  }
  return null;
}

/// [audio] as the bytes to write for this segment's output format.
///
/// A wav run against a model that serves headerless samples is the one case where
/// the provider's bytes are not yet a file: they need a header saying what rate
/// and channel layout they have, or nothing will play them. Everything else — mp3
/// and natively-served wav — is already a finished container.
///
/// The rate comes from the response rather than from config. A response that
/// omits it is a hard error naming the model, since a header with an invented rate
/// plays at the wrong pitch, which is worse than no file.
Uint8List _asWav(NarrationConfig config, GeneratedAudio audio) {
  final pcmSourced =
      config.outputFormat == TtsAudioFormat.wav &&
      config.profile.wavResponseFormat == TtsWavResponseFormat.pcm;
  if (!pcmSourced) return Uint8List.fromList(audio.bytes);

  final rate = audio.sampleRate;
  if (rate == null) {
    throw StateError(
      'Model "${config.profile.id}" returned raw samples without a sample '
      'rate, so a WAV header cannot be written. Set "wav_response_format" to '
      '"wav" if the provider serves WAV containers directly.',
    );
  }
  return Uint8List.fromList([
    ...wavHeader(
      sampleRate: rate,
      channels: audio.channels ?? 1,
      dataBytes: audio.bytes.length,
    ),
    ...audio.bytes,
  ]);
}

/// The trailing extension of a recorded segment filename, without the dot.
String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? '' : fileName.substring(dot + 1);
}

void _writeManifest(
  Directory outDir,
  NarrationConfig config,
  List<Map<String, Object?>> records,
  int paragraphsTotal,
  int count, {
  String? combinedFile,
  int? combinedBytes,
}) {
  final manifest = {
    'model': config.profile.id,
    'voice': config.voice,
    if (config.voiceLabel != null && config.voiceLabel != config.voice)
      'voice_label': config.voiceLabel,
    // Only what was actually sent: a model that ignores `lang_code` has no
    // language to record.
    if (config.profile.sendsLanguageField && config.language != null)
      'language': config.language,
    'format': config.outputFormat.wireValue,
    'max_segment_length': config.sendWholeFile
        ? maxWholeFileLength
        : _maxSegmentLength,
    // ignore: avoid_redundant_argument_values
    'paragraphs_total': paragraphsTotal,
    'paragraphs_narrated': records.length,
    'combined_file': ?combinedFile,
    'combined_bytes': ?combinedBytes,
    'segments_deleted': false,
    'paragraphs': records,
  };
  writeManifest(outDir, manifest);
}
