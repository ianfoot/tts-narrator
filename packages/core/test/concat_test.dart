import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/concat.dart';

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
  String writeWavBytes(String name, List<int> pcm) =>
      write(name, wavFileBytes(pcm, sampleRate: 24000));

  group('concatSegments', () {
    test('joins mp3 files byte-for-byte in order', () {
      final a = write('a.mp3', [1, 2, 3]);
      final b = write('b.mp3', [4, 5, 6, 7]);
      final out = '${dir.path}/joined.mp3';

      final result = concatSegments([a, b], outputPath: out, format: 'mp3');

      expect(result, out);
      expect(File(out).readAsBytesSync(), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('pcm strips each RIFF header and writes one WAV', () {
      final a = writeWavBytes('a.wav', [1, 2, 3]);
      final b = writeWavBytes('b.wav', [4, 5]);
      final out = '${dir.path}/joined.wav';

      concatSegments([a, b], outputPath: out, format: 'pcm');

      final joined = File(out).readAsBytesSync();
      final pcm = pcmPayload(joined);
      expect(pcm, [1, 2, 3, 4, 5]);
    });

    test('throws when a segment file is missing', () {
      expect(
        () => concatSegments(
          ['${dir.path}/nope.mp3'],
          outputPath: '${dir.path}/out.mp3',
          format: 'mp3',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws when there are no segments', () {
      expect(
        () => concatSegments(
          const [],
          outputPath: '${dir.path}/out.mp3',
          format: 'mp3',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws when a pcm segment is not a WAV container', () {
      final notWav = write('bad.bin', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
      expect(
        () => concatSegments(
          [notWav],
          outputPath: '${dir.path}/out.wav',
          format: 'pcm',
        ),
        throwsA(isA<FileSystemException>()),
      );
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

/// Builds a full WAV file's bytes for [pcm] at [sampleRate] — a RIFF header
/// wrapping the raw PCM payload, mirroring wav.dart's layout.
Uint8List wavFileBytes(List<int> pcm, {int sampleRate = 24000}) {
  final bytes = BytesBuilder(copy: false);
  void ascii(String s) => bytes.add(s.codeUnits);
  void u32(int v) => bytes.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  void u16(int v) => bytes.add(
    (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List(),
  );

  final byteRate = sampleRate * 2;
  ascii('RIFF');
  u32(36 + pcm.length);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(byteRate);
  u16(2);
  u16(16);
  ascii('data');
  u32(pcm.length);
  bytes.add(pcm);
  return bytes.takeBytes();
}

/// Extracts the `data` payload from a WAV file's bytes (concat helper).
List<int> pcmPayload(Uint8List wav) {
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final id = String.fromCharCodes(wav.sublist(offset, offset + 4));
    final size = ByteData.sublistView(wav).getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      return wav.sublist(offset + 8, offset + 8 + size);
    }
    offset += 8 + size;
  }
  throw StateError('no data chunk');
}
