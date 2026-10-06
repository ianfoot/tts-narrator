import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/audio_format.dart';
import 'package:tts_narrator_core/src/narration/concat.dart';
import 'package:tts_narrator_core/src/narration/wav.dart';

import 'support/wav_bytes.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_concat_test_');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  String write(String name, List<int> bytes) {
    final file = File('${dir.path}/$name')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  /// Minimal WAV: RIFF header wrapper around a raw PCM payload.
  String writeWavBytes(String name, List<int> pcm, {int sampleRate = 24000}) =>
      write(name, wavFileBytes(pcm, sampleRate: sampleRate));

  group('concatSegments', () {
    test('joins mp3 files byte-for-byte in order', () {
      final a = write('a.mp3', [1, 2, 3]);
      final b = write('b.mp3', [4, 5, 6, 7]);
      final out = '${dir.path}/joined.mp3';

      final result = concatSegments(
        [a, b],
        outputPath: out,
        format: TtsAudioFormat.mp3,
      );

      expect(result, out);
      expect(File(out).readAsBytesSync(), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('wav strips each RIFF header and writes one WAV', () {
      final a = writeWavBytes('a.wav', [1, 2, 3]);
      final b = writeWavBytes('b.wav', [4, 5]);
      final out = '${dir.path}/joined.wav';

      concatSegments([a, b], outputPath: out, format: TtsAudioFormat.wav);

      final joined = File(out).readAsBytesSync();
      expect(wavDataPayload(joined), [1, 2, 3, 4, 5]);
    });

    test('wav reuses the first segment header, rate included', () {
      // The pooled track has a different length than any single segment, so a
      // stale header would misreport its duration. Copying the `fmt ` chunk is
      // what keeps the sample rate correct without core knowing the rate.
      final a = writeWavBytes('a.wav', [1, 2, 3], sampleRate: 44100);
      final b = writeWavBytes('b.wav', [4, 5], sampleRate: 44100);
      final out = '${dir.path}/joined.wav';

      concatSegments([a, b], outputPath: out, format: TtsAudioFormat.wav);

      final joined = File(out).readAsBytesSync();
      expect(wavDataPayload(joined), [1, 2, 3, 4, 5]);
      expect(
        readWav(joined).formatChunk,
        readWav(File(a).readAsBytesSync()).formatChunk,
      );
    });

    test('wav rejects a segment whose audio layout differs', () {
      final a = writeWavBytes('a.wav', [1, 2, 3], sampleRate: 44100);
      final b = writeWavBytes('b.wav', [4, 5], sampleRate: 16000);
      expect(
        () => concatSegments(
          [a, b],
          outputPath: '${dir.path}/joined.wav',
          format: TtsAudioFormat.wav,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws when a segment file is missing', () {
      expect(
        () => concatSegments(
          ['${dir.path}/nope.mp3'],
          outputPath: '${dir.path}/out.mp3',
          format: TtsAudioFormat.mp3,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws when there are no segments', () {
      expect(
        () => concatSegments(
          const [],
          outputPath: '${dir.path}/out.mp3',
          format: TtsAudioFormat.mp3,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws when a wav segment is not a WAV container', () {
      final notWav = write('bad.bin', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
      expect(
        () => concatSegments(
          [notWav],
          outputPath: '${dir.path}/out.wav',
          format: TtsAudioFormat.wav,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('combinedFilePath', () {
    test('null when no manifest exists', () {
      expect(combinedFilePath(dir.path), isNull);
    });

    test('null when the manifest has no combined_file', () {
      write(
        'manifest.json',
        utf8.encode(const JsonEncoder().convert({'format': 'mp3'})),
      );
      expect(combinedFilePath(dir.path), isNull);
    });

    test('null when the combined file is missing from disk', () {
      write(
        'manifest.json',
        utf8.encode(
          const JsonEncoder().convert({'combined_file': 'story_full.mp3'}),
        ),
      );
      expect(combinedFilePath(dir.path), isNull);
    });

    test('returns the absolute path when the file exists', () {
      write(
        'manifest.json',
        utf8.encode(
          const JsonEncoder().convert({'combined_file': 'story_full.mp3'}),
        ),
      );
      write('story_full.mp3', [9, 9]);
      expect(combinedFilePath(dir.path), '${dir.path}/story_full.mp3');
    });

    test('null for a missing directory', () {
      expect(combinedFilePath('${dir.path}/nope'), isNull);
    });
  });

  group('segmentCleanupAvailable / cleanupSegmentFiles', () {
    test('true only when the manifest has undeleted, present segments', () {
      write(
        'manifest.json',
        utf8.encode(
          const JsonEncoder().convert({
            'format': 'mp3',
            'combined_file': 'story_full.mp3',
            'segments_deleted': false,
            'paragraphs': [
              {'index': 1, 'wav': 'story_1.mp3'},
              {'index': 2, 'wav': 'story_2.mp3'},
            ],
          }),
        ),
      );
      write('story_full.mp3', [9, 9]);
      write('story_1.mp3', [1]);
      write('story_2.mp3', [2]);

      expect(segmentCleanupAvailable(dir.path), isTrue);
    });

    test('false when segments are already deleted', () {
      write(
        'manifest.json',
        utf8.encode(
          const JsonEncoder().convert({
            'format': 'mp3',
            'combined_file': 'story_full.mp3',
            'segments_deleted': true,
            'paragraphs': [
              {'index': 1, 'wav': 'story_1.mp3'},
            ],
          }),
        ),
      );
      write('story_full.mp3', [9, 9]);
      write('story_1.mp3', [1]);

      expect(segmentCleanupAvailable(dir.path), isFalse);
    });

    test('false when nobody runs in the directory', () {
      expect(segmentCleanupAvailable(dir.path), isFalse);
    });

    test('false when no combined file is on disk', () {
      write(
        'manifest.json',
        utf8.encode(
          const JsonEncoder().convert({
            'format': 'mp3',
            'combined_file': 'story_full.mp3',
            'segments_deleted': false,
            'paragraphs': [
              {'index': 1, 'wav': 'story_1.mp3'},
            ],
          }),
        ),
      );
      write('story_1.mp3', [1]);

      expect(segmentCleanupAvailable(dir.path), isFalse);
    });

    test('deletes segment files but keeps the combined file and manifest', () {
      write(
        'manifest.json',
        utf8.encode(
          const JsonEncoder().convert({
            'format': 'mp3',
            'combined_file': 'story_full.mp3',
            'segments_deleted': false,
            'paragraphs': [
              {'index': 1, 'wav': 'story_1.mp3'},
              {'index': 2, 'wav': 'story_2.mp3'},
            ],
          }),
        ),
      );
      write('story_full.mp3', [9, 9]);
      write('story_1.mp3', [1]);
      write('story_2.mp3', [2]);

      final removed = cleanupSegmentFiles(dir.path);

      expect(removed, 2);
      expect(File('${dir.path}/story_1.mp3').existsSync(), isFalse);
      expect(File('${dir.path}/story_2.mp3').existsSync(), isFalse);
      expect(File('${dir.path}/story_full.mp3').existsSync(), isTrue);
      final manifest = jsonDecode(
        File('${dir.path}/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(manifest['segments_deleted'], isTrue);
      // The combined file + manifest survive so cleanup is idempotent.
      expect(cleanupSegmentFiles(dir.path), 0);
    });
  });
}

/// Extracts the `data` payload from a WAV file's bytes.
Uint8List wavDataPayload(List<int> wav) =>
    readWav(Uint8List.fromList(wav)).data;
