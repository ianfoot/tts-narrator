import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/voice_config.dart';
import 'package:tts_narrator_core/src/config/voice_config_io.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';

void main() {
  group('loadVoiceConfig', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tts_config_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    void writeGlobal(String contents) =>
        File('${dir.path}${Platform.pathSeparator}config.json')
            .writeAsStringSync(contents);

    void writeModel(String alias, String contents) =>
        File('${dir.path}${Platform.pathSeparator}$alias.json')
            .writeAsStringSync(contents);

    (VoiceConfig, List<String>) load() => loadVoiceConfig(dir.path);

    test('missing directory yields an empty config and no warnings', () {
      final (cfg, warnings) = load();
      expect(cfg.isEmpty, isTrue);
      expect(cfg.defaultModel, isNull);
      expect(cfg.providers, isEmpty);
      expect(cfg.voices, isEmpty);
      expect(warnings, isEmpty);
    });

    test('parses per-model files into request profiles', () {
      writeModel(
        'gemini',
        '''{"id":"google/gemini-3.1-flash-tts-preview","provider":"openrouter","format":"pcm","sample_rate":24000,"prompt_style":true}''',
      );
      final (cfg, warnings) = load();
      expect(cfg.models.containsKey('gemini'), isTrue);
      expect(warnings, isEmpty);
    });

    group('speed capability', () {
      TtsModelProfile loadProfile(String json) {
        writeModel('m', json);
        return load().$1.models['m']!;
      }

      test('defaults to unsupported when the key is absent', () {
        expect(
          loadProfile('{"id":"x/y","provider":"openrouter"}').supportsSpeed,
          isFalse,
        );
      });

      test('reads the opt-in flag', () {
        expect(
          loadProfile('{"id":"x/y","provider":"openrouter","speed":true}')
              .supportsSpeed,
          isTrue,
        );
        expect(
          loadProfile('{"id":"x/y","provider":"openrouter","speed":false}')
              .supportsSpeed,
          isFalse,
        );
      });

      test('rejects a non-bool', () {
        writeModel('m', '{"id":"x/y","provider":"openrouter","speed":"yes"}');
        final (_, warnings) = load();
        expect(warnings.single, contains('"speed" must be a bool'));
      });
    });

    test(
      'accepts a directory with only an empty config.json and no models',
      () {
        writeGlobal('{}');
        final (cfg, warnings) = load();
        expect(cfg.isEmpty, isTrue);
      },
    );
  });

  group('defaultConfigDir', () {
    test('uses standard cross-platform config directory', () {
      final path = defaultConfigDir();
      expect(path.contains('tts-narrator'), isTrue);
    });
  });

  group('writeVoiceConfig', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tts_write_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes config.json', () {
      final cfg = VoiceConfig(defaultModel: 'fish');
      writeVoiceConfig(dir.path, cfg);
      expect(
        File('${dir.path}${Platform.pathSeparator}config.json').existsSync(),
        isTrue,
      );
    });

    test('round-trips the speed capability through a model file', () {
      writeVoiceConfig(
        dir.path,
        VoiceConfig(
          defaultModel: 'fast',
          models: {
            'fast': const TtsModelProfile(
              alias: 'fast',
              id: 'x/y',
              supportsSpeed: true,
            ),
            'plain': const TtsModelProfile(alias: 'plain', id: 'x/z'),
          },
        ),
      );

      final raw = jsonDecode(
        File('${dir.path}${Platform.pathSeparator}fast.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(raw['speed'], isTrue);

      final (cfg, warnings) = loadVoiceConfig(dir.path);
      expect(warnings, isEmpty);
      expect(cfg.models['fast']!.supportsSpeed, isTrue);
      expect(cfg.models['plain']!.supportsSpeed, isFalse);
    });
  });
}
