import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/manifest.dart';

void main() {
  late Directory dir;

  setUp(
    () => dir = Directory.systemTemp.createTempSync('tts_narrator_manifest_'),
  );
  tearDown(() => dir.deleteSync(recursive: true));

  group('readManifest', () {
    test('returns null when no manifest exists', () {
      expect(readManifest(dir), isNull);
    });

    test('returns null on malformed JSON', () {
      File('${dir.path}/manifest.json').writeAsStringSync('not json{{');
      expect(readManifest(dir), isNull);
    });

    test('returns null when the document is a JSON array', () {
      File('${dir.path}/manifest.json').writeAsStringSync('[1, 2]');
      expect(readManifest(dir), isNull);
    });

    test('returns the whole document, not just its paragraphs', () {
      File('${dir.path}/manifest.json').writeAsStringSync(
        jsonEncode({
          'combined_file': 'story_full.mp3',
          'paragraphs': [
            {'index': 1},
          ],
        }),
      );
      expect(readManifest(dir)!['combined_file'], 'story_full.mp3');
    });
  });

  group('paragraphRecords', () {
    test('returns empty when no manifest exists', () {
      expect(paragraphRecords(dir), isEmpty);
    });

    test('returns empty on malformed JSON', () {
      File('${dir.path}/manifest.json').writeAsStringSync('not json{{');
      expect(paragraphRecords(dir), isEmpty);
    });

    test('returns empty when paragraphs is absent', () {
      File('${dir.path}/manifest.json')
          .writeAsStringSync(jsonEncode({'combined_file': 'story_full.mp3'}));
      expect(paragraphRecords(dir), isEmpty);
    });

    test('returns empty when paragraphs is not a list', () {
      File('${dir.path}/manifest.json')
          .writeAsStringSync(jsonEncode({'paragraphs': 'none'}));
      expect(paragraphRecords(dir), isEmpty);
    });

    test('skips entries that are not objects', () {
      File('${dir.path}/manifest.json').writeAsStringSync(
        jsonEncode({
          'paragraphs': [
            'stray',
            7,
            {'index': 1},
          ],
        }),
      );
      expect(paragraphRecords(dir), hasLength(1));
    });

    test('parses records from a valid manifest', () {
      File('${dir.path}/manifest.json').writeAsStringSync(
        jsonEncode({
          'paragraphs': [
            {'index': 1, 'prompt': 'A.', 'wav': 'story_1.mp3'},
            {'index': 2, 'prompt': 'B.', 'wav': 'story_2.mp3'},
          ],
        }),
      );
      final records = paragraphRecords(dir);
      expect(records, hasLength(2));
      expect(records.first['index'], 1);
      expect(records.last['prompt'], 'B.');
    });
  });

  group('writeManifest', () {
    test('round-trips every key it was handed', () {
      final manifest = <String, dynamic>{
        'model': 'gemini-2.5-flash',
        'voice': 'Charon',
        'combined_file': 'story_full.mp3',
        'segments_deleted': true,
        'paragraphs': [
          {'index': 1, 'prompt': 'A.', 'wav': 'story_1.mp3'},
        ],
      };
      writeManifest(dir, manifest);

      final file = File('${dir.path}/manifest.json');
      expect(file.existsSync(), isTrue);
      expect(readManifest(dir), manifest);
      // Indented, so a manifest a user opened by hand stays readable.
      expect(file.readAsStringSync(), contains('\n  "paragraphs"'));
    });

    test('overwrites a previous manifest rather than appending', () {
      writeManifest(dir, {
        'paragraphs': [
          {'index': 1},
        ],
      });
      writeManifest(dir, {'paragraphs': []});
      expect(paragraphRecords(dir), isEmpty);
    });
  });

  group('resolveInManifestDir', () {
    test('resolves a recorded name against the run directory', () {
      expect(
        resolveInManifestDir(dir, 'story_1.mp3'),
        '${dir.path}/story_1.mp3',
      );
    });
  });
}
