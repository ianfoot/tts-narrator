import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/cli/voice_config.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';

void main() {
  group('loadVoiceConfig', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tts_config_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    String write(String contents) {
      final f = File('${dir.path}/voice_config.json')..writeAsStringSync(contents);
      return f.path;
    }

    test('missing file yields an empty config', () {
      final cfg = loadVoiceConfig('${dir.path}/nope.json');
      expect(cfg.isEmpty, isTrue);
      expect(cfg.apiKey, isNull);
      expect(cfg.aliases, isEmpty);
    });

    test('parses api_key and per-model aliases', () {
      final path = write(jsonSample(
        apiKey: 'sk-or-test',
        voices: {
          'fish': {'Narrator': 'hex1'},
          'kokoro': {'Emma': 'bf_emma'},
        },
      ));
      final cfg = loadVoiceConfig(path);
      expect(cfg.apiKey, 'sk-or-test');
      expect(cfg.aliases['fish']?['Narrator'], 'hex1');
      expect(cfg.aliases['kokoro']?['Emma'], 'bf_emma');
    });

    test('accepts a file with no api_key and no voices', () {
      final path = write('{"voices": {}}');
      final cfg = loadVoiceConfig(path);
      expect(cfg.isEmpty, isTrue);
    });

    test('throws VoiceConfigError on malformed JSON', () {
      final path = write('{not json');
      expect(() => loadVoiceConfig(path), throwsA(isA<VoiceConfigError>()));
    });

    test('throws VoiceConfigError on non-object top level', () {
      final path = write('[1,2,3]');
      expect(() => loadVoiceConfig(path), throwsA(isA<VoiceConfigError>()));
    });

    test('throws VoiceConfigError on non-string api_key', () {
      final path = write('{"api_key": 123}');
      expect(() => loadVoiceConfig(path), throwsA(isA<VoiceConfigError>()));
    });

    test('ignores non-string voice id values, keeps the model key only if non-empty', () {
      final path = write('''{"voices": {"fish": {"A": "id1", "B": 42, "C": ""}}}''');
      final cfg = loadVoiceConfig(path);
      expect(cfg.aliases['fish']?['A'], 'id1');
      expect(cfg.aliases['fish']?.containsKey('B'), isFalse);
      expect(cfg.aliases['fish']?.containsKey('C'), isFalse);
    });
  });

  group('resolveVoice', () {
    final cfg = VoiceConfig(apiKey: 'k', aliases: {
      'fish': {'British Female Narrator (good)': '89f41ea'},
      'kokoro': {'Emma': 'bf_emma'},
    });

    test('resolves an alias to its raw id and keeps the label', () {
      final (id, label) = cfg.resolveVoice('fish', 'British Female Narrator (good)');
      expect(id, '89f41ea');
      expect(label, 'British Female Narrator (good)');
    });

    test('passes unknown values through unchanged', () {
      final (id, label) = cfg.resolveVoice('fish', '2fd511bd06904a21a971c6551dfb853a');
      expect(id, '2fd511bd06904a21a971c6551dfb853a');
      expect(label, '2fd511bd06904a21a971c6551dfb853a');
    });

    test('is isolated per model', () {
      final (id, _) = cfg.resolveVoice('kokoro', 'British Female Narrator (good)');
      expect(id, 'British Female Narrator (good)'); // not a kokoro alias
      final (id2, _) = cfg.resolveVoice('gemini', 'Emma');
      expect(id2, 'Emma');
    });

    test('empty config passes everything through', () {
      final (id, label) = const VoiceConfig().resolveVoice('fish', 'anything');
      expect(id, 'anything');
      expect(label, 'anything');
    });
  });

  group('voiceEntries', () {
    test('gemini yields its known voices, sorted, no aliases', () {
      final entries =
          voiceEntries(model: kGeminiProfile, config: const VoiceConfig());
      expect(entries, hasLength(kGeminiProfile.voices.length));
      expect(entries.every((e) => e.model == 'gemini'), isTrue);
      expect(entries.firstWhere((e) => e.id == 'Charon').isAlias, isFalse);
      final labels = entries.map((e) => e.label.toLowerCase()).toList();
      expect(labels, orderedEquals([...labels]..sort()));
    });

    test('kokoro (free-form) still lists its known voices + default', () {
      final entries =
          voiceEntries(model: kKokoroProfile, config: const VoiceConfig());
      expect(entries.any((e) => e.id == 'bf_emma'), isTrue);
      expect(entries.any((e) => e.id == 'bm_lewis'), isTrue);
    });

    test('fish (free-form) includes aliases and its default voice', () {
      final cfg = VoiceConfig(aliases: {
        'fish': {'Narrator': 'hex1'},
      });
      final entries = voiceEntries(model: kFishProfile, config: cfg);
      expect(
        entries.any(
          (e) => e.id == 'hex1' && e.label == 'Narrator' && e.isAlias,
        ),
        isTrue,
      );
      expect(entries.any((e) => e.id == kFishProfile.defaultVoice), isTrue);
    });

    test('labels the default voice with its friendly name', () {
      final entries =
          voiceEntries(model: kFishProfile, config: const VoiceConfig());
      expect(
        entries.any(
          (e) => e.id == kFishProfile.defaultVoice &&
              e.label == 'British Female Narrator',
        ),
        isTrue,
      );
    });

    test('dedupes the default voice when it doubles as an alias', () {
      final cfg = VoiceConfig(aliases: {
        'fish': {'Big Fish': kFishProfile.defaultVoice},
      });
      final entries = voiceEntries(model: kFishProfile, config: cfg);
      expect(
        entries.where((e) => e.id == kFishProfile.defaultVoice),
        hasLength(1),
      );
    });

    test('covers all models when none is given', () {
      final entries = voiceEntries(config: const VoiceConfig());
      expect(entries.map((e) => e.model).toSet(), {'gemini', 'kokoro', 'fish'});
    });
  });

  group('writeVoiceConfig', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tts_config_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('round-trips api_key and aliases', () {
      final path = '${dir.path}/write_test/voice_config.json';
      writeVoiceConfig(
        path,
        VoiceConfig(
          apiKey: 'sk-or-test',
          aliases: {
            'fish': {'Narrator': 'hex1'},
            'kokoro': {'Emma': 'bf_emma'},
          },
        ),
      );
      final cfg = loadVoiceConfig(path);
      expect(cfg.apiKey, 'sk-or-test');
      expect(cfg.aliases['fish']?['Narrator'], 'hex1');
      expect(cfg.aliases['kokoro']?['Emma'], 'bf_emma');
    });

    test('omits empty sections rather than writing nulls', () {
      final path = '${dir.path}/voice_config.json';
      writeVoiceConfig(path, const VoiceConfig());
      expect(File(path).readAsStringSync(), contains('{}'));
    });

    test('creates missing parent directories', () {
      final path =
          '${dir.path}/a/b/c/voice_config.json';
      writeVoiceConfig(path, const VoiceConfig(apiKey: 'k'));
      expect(File(path).existsSync(), isTrue);
    });

    test('throws VoiceConfigError when the path cannot be written', () {
      final path = '/dev/null/voice_config.json';
      expect(
        () => writeVoiceConfig(path, const VoiceConfig(apiKey: 'k')),
        throwsA(isA<VoiceConfigError>()),
      );
    });
  });

  group('defaultConfigPath', () {
    test('always ends with the config filename', () {
      expect(defaultConfigPath(), endsWith('voice_config.json'));
    });

    test('uses the Unix config dir on non-Windows hosts', () {
      if (Platform.isWindows) return;
      final p = defaultConfigPath();
      expect(p, contains('.config/tts-narrator'));
    });
  });
}

String jsonSample({String? apiKey, Map<String, Map<String, String>> voices = const {}}) {
  final out = <String, Object?>{};
  if (apiKey != null) out['api_key'] = apiKey;
  out['voices'] = voices;
  return const JsonEncoder().convert(out);
}