import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/config.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';
import 'package:tts_narrator_core/src/narration/narration.dart';

void main() {
  group('chunkText', () {
    test('splits paragraphs on blank lines and trims (minWords 1)', () {
      final chunks = chunkText('Para one.\n\n\n  Para two.  \n\nPara three.',
          minWords: 1);
      expect(chunks, ['Para one.', 'Para two.', 'Para three.']);
    });

    test('default minWords merges short paragraphs together', () {
      final chunks = chunkText('Para one.\n\n\n  Para two.  \n\nPara three.');
      expect(chunks, ['Para one. Para two. Para three.']);
    });

    test('normalizes CRLF; lone CR becomes a newline within a paragraph', () {
      expect(chunkText('One.\r\n\r\nTwo.\rThree.', minWords: 1),
          ['One.', 'Two.\nThree.']);
    });

    test('drops empty paragraphs and returns nothing for blank input', () {
      expect(chunkText('   \n\n  '), isEmpty);
    });

    test('merges a short paragraph into the following long one', () {
      final chunks = chunkText(
          'Alpha\n\nBeta beta beta. And more words here.', minWords: 5);
      expect(chunks, ['Alpha', 'Beta beta beta. And more words here.']);
    });

    test('a leading short paragraph is not merged (no predecessor)', () {
      final chunks = chunkText('Alpha\n\nBeta beta beta. And more words here.',
          minWords: 5);
      expect(chunks[0], 'Alpha');
      expect(chunks[1], 'Beta beta beta. And more words here.');
    });

    test('merges a short paragraph that follows a long one', () {
      final chunks = chunkText(
          'one two three four five\n\nshort\n\nanother long paragraph here ok',
          minWords: 5);
      expect(chunks, ['one two three four five short', 'another long paragraph here ok']);
    });

    test('consecutive short paragraphs pack into the final merge', () {
      final chunks = chunkText('a\n\nb\n\nc d e f g h', minWords: 3);
      expect(chunks, ['a b', 'c d e f g h']);
    });
  });

  group('chunkText long split', () {
    test('splits an over-cap paragraph at sentence boundaries', () {
      // Deterministic long paragraph: 300 short sentences.
      final sentences = List.generate(300, (i) => 'This is sentence $i.', growable: true);
      final para = sentences.join(' ');
      expect(para.length, greaterThan(4000));

      final chunks = chunkText(para);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(4000 + 1));
      }
      // Every chunk ends on a sentence boundary (period + optional space).
      for (final c in chunks) {
        expect(c.trimRight().endsWith('.'), isTrue);
      }
    });

    test('keeps an under-cap paragraph whole', () {
      final para = List.filled(30, 'Hello world. ').join();
      expect(chunkText(para), [para.trim()]);
    });
  });

  group('inputStem', () {
    test('strips directory and extension, lowercases, slugs non-alnum', () {
      expect(inputStem('/foo/bar/A Shorts Story Draft 5.txt'),
          'a_shorts_story_draft_5');
    });

    test('handles no extension and trailing separator', () {
      expect(inputStem('/x/y/story'), 'story');
      expect(inputStem('story.txt'), 'story');
    });
  });

  group('output dir helpers', () {
    const gemini = TtsModelProfile(
      alias: 'gemini',
      id: 'google/gemini-3.1-flash-tts-preview',
      format: 'pcm',
      sampleRate: 24000,
    );
    NarrationConfig cfg(String input, String out) => NarrationConfig(
          inputPath: input,
          profile: gemini,
          voice: 'Callirrhoe',
          outDir: out,
        );

    test('outDirBasename takes the last component', () {
      expect(outDirBasename('/a/b/c'), 'c');
      expect(outDirBasename('output'), 'output');
    });

    test('appends the stem when out dir does not end with it', () {
      expect(outputDirPath(cfg('story.txt', 'output')), 'output/story');
    });

    test('avoids double-append when out dir already ends with the stem', () {
      expect(outputDirPath(cfg('story.txt', 'output/story')), 'output/story');
    });
  });

  group('fingerprintOf', () {
    test('is deterministic and stable for known bytes', () {
      expect(fingerprintOf([1, 2, 3, 4]), fingerprintOf([1, 2, 3, 4]));
      // Regression lock for the exact hash of an empty byte list.
      expect(fingerprintOf(<int>[]), '811c9dc501000193');
    });

    test('differs for different bytes', () {
      expect(fingerprintOf([1]), isNot(fingerprintOf([2])));
      expect(fingerprintOf([1, 2]), isNot(fingerprintOf([2, 1])));
    });
  });

  group('resumeMatch', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tts_narrator_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Map<String, Object?> record(int index, String prompt, String wav) =>
        {'index': index, 'prompt': prompt, 'wav': wav};

    test('matches on index+prompt when the file exists', () {
      File('${dir.path}/story_1.mp3').writeAsStringSync('x');
      final existing = [record(1, 'Hello.', 'story_1.mp3')];
      final m = resumeMatch(existing, 1, 'Hello.', dir.path);
      expect(m, isNotNull);
      expect(m!['wav'], 'story_1.mp3');
    });

    test('no match when the file is missing', () {
      final existing = [record(1, 'Hello.', 'story_1.mp3')];
      expect(resumeMatch(existing, 1, 'Hello.', dir.path), isNull);
    });

    test('no match on different index or prompt', () {
      File('${dir.path}/story_1.mp3').writeAsStringSync('x');
      final existing = [record(1, 'Hello.', 'story_1.mp3')];
      expect(resumeMatch(existing, 2, 'Hello.', dir.path), isNull);
      expect(resumeMatch(existing, 1, 'Different.', dir.path), isNull);
    });

    test('empty existing list yields null', () {
      expect(resumeMatch(const [], 1, 'Hello.', dir.path), isNull);
    });
  });

  group('readManifestRecords', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tts_narrator_manifest_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('returns empty when no manifest exists', () {
      expect(readManifestRecords(dir), isEmpty);
    });

    test('returns empty on malformed JSON', () {
      File('${dir.path}/manifest.json').writeAsStringSync('not json{{');
      expect(readManifestRecords(dir), isEmpty);
    });

    test('parses records from a valid manifest', () {
      File('${dir.path}/manifest.json').writeAsStringSync(jsonEncode({
        'paragraphs': [
          {'index': 1, 'prompt': 'A.', 'wav': 'story_1.mp3'},
          {'index': 2, 'prompt': 'B.', 'wav': 'story_2.mp3'},
        ],
      }));
      final records = readManifestRecords(dir);
      expect(records, hasLength(2));
      expect(records.first['index'], 1);
      expect(records.last['prompt'], 'B.');
    });
  });
}