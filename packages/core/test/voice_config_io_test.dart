import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/cli/voice_config.dart';
import 'package:tts_narrator_core/src/cli/voice_config_io.dart';

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
      writeModel('gemini', '''{"id":"google/gemini-3.1-flash-tts-preview","provider":"openrouter","format":"pcm","sample_rate":24000,"prompt_style":true}''');
      final (cfg, warnings) = load();
      expect(cfg.models.containsKey('gemini'), isTrue);
      expect(warnings, isEmpty);
    });

    test('accepts a directory with only an empty config.json and no models', () {
      writeGlobal('{}');
      final (cfg, warnings) = load();
      expect(cfg.isEmpty, isTrue);
    });
  });

  group('defaultConfigDir', () {
    test('uses Unix config dir on non-Windows hosts', () {
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
      expect(File('${dir.path}${Platform.pathSeparator}config.json').existsSync(), isTrue);
    });
  });
}