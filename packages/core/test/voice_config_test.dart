import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/cli/voice_config.dart';
import 'package:tts_narrator_core/src/cli/voice_config_queries.dart';
import 'package:tts_narrator_core/src/cli/voice_config_io.dart';
import 'package:tts_narrator_core/src/narration/cost.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';

void main() {
  group('loadVoiceConfig', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tts_config_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    void writeGlobal(String contents) {
      File('${dir.path}${Platform.pathSeparator}config.json')
          .writeAsStringSync(contents);
    }

    void writeModel(String alias, String contents) {
      File('${dir.path}${Platform.pathSeparator}$alias.json')
          .writeAsStringSync(contents);
    }

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
      writeModel('gemini', '''{
  "id": "google/gemini-3.1-flash-tts-preview",
  "provider": "openrouter",
  "format": "pcm",
  "sample_rate": 24000,
  "prompt_style": true
}''');
      writeModel(
        'kokoro',
        '{"id": "hexgrad/kokoro-82m", "provider": "openrouter", "format": "mp3"}',
      );
      writeModel(
        'fish',
        '{"id": "fish-audio/s2.1-pro-free", "provider": "openrouter", "format": "mp3"}',
      );
      final (cfg, _) = load();
      expect(cfg.models, hasLength(3));
      expect(cfg.models['gemini']?.id, 'google/gemini-3.1-flash-tts-preview');
      expect(cfg.models['gemini']?.format, 'pcm');
      expect(cfg.models['gemini']?.sampleRate, 24000);
      expect(cfg.models['gemini']?.promptStyle, isTrue);
      expect(cfg.models['gemini']?.sendsVoiceField, isTrue);
      expect(cfg.models['kokoro']?.format, 'mp3');
      expect(cfg.models['fish']?.id, 'fish-audio/s2.1-pro-free');
    });

    test('defaults model fields apply when omitted', () {
      writeModel('x', '{"id": "a/b", "provider": "openrouter"}');
      final (cfg, _) = load();
      final m = cfg.models['x']!;
      expect(m.format, 'mp3');
      expect(m.promptStyle, isFalse);
      expect(m.sendsVoiceField, isTrue);
      expect(m.sampleRate, isNull);
    });

    test('parses an optional display_name into the profile', () {
      writeModel(
        'gemini',
        '{"id": "google/gemini-3.1-flash-tts-preview", "provider": "openrouter", "display_name": "Gemini 3.1 Flash TTS"}',
      );
      final (cfg, _) = load();
      final m = cfg.models['gemini']!;
      expect(m.displayName, 'Gemini 3.1 Flash TTS');
    });

    test('display_name defaults to null when omitted', () {
      writeModel('x', '{"id": "a/b", "provider": "openrouter"}');
      final (cfg, _) = load();
      expect(cfg.models['x']!.displayName, isNull);
    });

    test('a non-string display_name skips the model with a warning', () {
      writeModel(
        'x',
        '{"id": "a/b", "provider": "openrouter", "display_name": 7}',
      );
      final (cfg, warnings) = load();
      expect(cfg.models.containsKey('x'), isFalse);
      expect(warnings.join('\n'), contains('display_name'));
    });

    test('parses per-model default_voice, pricing and voices', () {
      writeModel('fish', '''
{
  "id": "fish-audio/s2.1-pro-free",
  "provider": "openrouter",
  "default_voice": "Narrator",
  "pricing": {"usd_per_m_chars": 0.62},
  "voices": {"Narrator": "hex1", "Emma": "bf_emma"}
}''');
      writeModel(
        'kokoro',
        '{"id": "hexgrad/kokoro-82m", "provider": "openrouter", "voices": {"Emma": "bf_emma"}}',
      );
      final (cfg, _) = load();
      expect(cfg.defaults['fish'], 'Narrator');
      expect(cfg.pricing['fish']?.usdPerMChars, 0.62);
      expect(cfg.voices['fish']?['Narrator']?.id, 'hex1');
      expect(cfg.voices['fish']?['Emma']?.id, 'bf_emma');
      expect(cfg.voices['kokoro']?['Emma']?.id, 'bf_emma');
    });

    test('parses voices as one object per voice with optional gender', () {
      writeModel('kokoro', '''
{
  "id": "a/b",
  "provider": "openrouter",
  "voices": {
    "Emma": {"id": "bf_emma", "gender": "female"},
    "Daniel": {"id": "bm_daniel", "gender": "male"},
    "Fable": {"id": "bm_fable"}
  }
}
''');
      writeModel('gemini', '{"id": "a/b", "provider": "openrouter"}');
      final (cfg, _) = load();
      expect(cfg.voices['kokoro']?['Emma']?.id, 'bf_emma');
      expect(cfg.voices['kokoro']?['Emma']?.gender, VoiceGender.female);
      expect(cfg.voices['kokoro']?['Daniel']?.gender, VoiceGender.male);
      // Untyped entries carry an id but no gender tag.
      expect(cfg.voices['kokoro']?['Fable']?.gender, isNull);
      // Untagged models carry no entries at all.
      expect(cfg.voices.containsKey('gemini'), isFalse);
    });

    test('accepts the legacy string shorthand for voices', () {
      writeModel('x', '''
{
  "id": "a/b",
  "provider": "openrouter",
  "voices": {"A": "id1", "B": 42, "C": ""}
}
''');
      final (cfg, _) = load();
      expect(cfg.voices['x']?['A']?.id, 'id1');
      expect(cfg.voices['x']?['A']?.gender, isNull);
      // Malformed entries are skipped.
      expect(cfg.voices['x']?.containsKey('B'), isFalse);
      expect(cfg.voices['x']?.containsKey('C'), isFalse);
    });

    test('skips malformed voice-object entries and bad genders quietly', () {
      writeModel('x', '''
{
  "id": "a/b",
  "provider": "openrouter",
  "voices": {
    "A": {"id": "ok1", "gender": "female"},
    "B": {"id": ""},
    "C": {"gender": "male"},
    "D": {"id": 42},
    "E": {"id": "ok2", "gender": "soprano"},
    "F": {"id": "ok3", "gender": "Male"}
  }
}
''');
      final (cfg, warnings) = load();
      expect(cfg.voices['x']?['A']?.gender, VoiceGender.female);
      expect(cfg.voices['x']?.containsKey('B'), isFalse);
      expect(cfg.voices['x']?.containsKey('C'), isFalse);
      expect(cfg.voices['x']?.containsKey('D'), isFalse);
      // Unrecognized gender strings are dropped, the voice kept.
      expect(cfg.voices['x']?['E']?.id, 'ok2');
      expect(cfg.voices['x']?['E']?.gender, isNull);
      // Case-insensitive gender parsing.
      expect(cfg.voices['x']?['F']?.gender, VoiceGender.male);
      expect(warnings, isEmpty);
    });

    test('rejects a non-object voices block', () {
      writeModel(
        'x',
        '{"id": "a/b", "provider": "openrouter", "voices": ["female"]}',
      );
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.single, contains('"voices"'));
    });

    test('skips a model file with no id and reports a warning', () {
      writeModel('x', '{"format": "mp3"}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.single, contains('Skipped model "x"'));
    });

    test('skips a malformed model file and keeps the rest loading', () {
      writeModel('good', '{"id": "a/b", "provider": "openrouter"}');
      writeModel('bad', '{not json');
      final (cfg, warnings) = load();
      expect(cfg.models.keys, ['good']);
      expect(warnings.single, contains('Skipped model "bad"'));
    });

    test('a wrong-typed model field is skipped with a warning', () {
      writeModel('x', '{"id": "a/b", "sample_rate": "lots"}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.single, contains('Skipped model "x"'));
    });

    test('model files are read in sorted filename order', () {
      writeModel('zebra', '{"id": "z/a", "provider": "openrouter"}');
      writeModel('alph', '{"id": "a/b", "provider": "openrouter"}');
      final (cfg, _) = load();
      expect(cfg.models.keys.toList(), ['alph', 'zebra']);
    });

    test(
      'accepts a directory with only an empty config.json and no models',
      () {
        writeGlobal('{}');
        final (cfg, _) = load();
        expect(cfg.isEmpty, isTrue);
      },
    );

    test(r'parses default_model and the providers block verbatim', () {
      writeGlobal('''{
  "default_model": "fish",
  "providers": {
    "openrouter": { "OPENROUTER_API_KEY": "\${OPENROUTER_API_KEY}" }
  }
}''');
      final (cfg, _) = load();
      expect(cfg.defaultModel, 'fish');
      // The `${...}` env reference is preserved as a literal, not resolved.
      expect(cfg.providers, {
        'openrouter': {'OPENROUTER_API_KEY': r'${OPENROUTER_API_KEY}'},
      });
    });

    test('rejects a non-string default_model (global config)', () {
      writeGlobal('{"default_model": 42}');
      expect(load, throwsA(isA<VoiceConfigurationError>()));
    });

    test('rejects malformed global config.json loudly', () {
      writeGlobal('{not json');
      expect(load, throwsA(isA<VoiceConfigurationError>()));
    });

    test('rejects a non-object top level in config.json', () {
      writeGlobal('[1,2,3]');
      expect(load, throwsA(isA<VoiceConfigurationError>()));
    });

    test('rejects a non-object providers entry', () {
      writeGlobal('{"providers": {"openrouter": "sk-or"}}');
      expect(load, throwsA(isA<VoiceConfigurationError>()));
    });

    test('rejects a non-string value inside a providers entry', () {
      writeGlobal('{"providers": {"openrouter": {"KEY": 42}}}');
      expect(load, throwsA(isA<VoiceConfigurationError>()));
    });

    test('parses the required model-file provider', () {
      writeModel('gemini', '{"id": "a/b", "provider": "google"}');
      writeModel('fish', '{"id": "a/b", "provider": "openrouter"}');
      final (cfg, _) = load();
      expect(cfg.models['gemini']?.provider, 'google');
      expect(cfg.models['fish']?.provider, 'openrouter');
    });

    test(
      'skips a model file with a missing provider and reports a warning',
      () {
        writeModel('x', '{"id": "a/b"}');
        final (cfg, warnings) = load();
        expect(cfg.models, isEmpty);
        expect(warnings.single, contains('Skipped model "x"'));
        expect(warnings.single, contains('"provider"'));
      },
    );

    test('an unknown default_model warns and keeps the fish fallback', () {
      writeGlobal('{"default_model": "bogus"}');
      writeModel('fish', '{"id": "a/b", "provider": "openrouter"}');
      final (cfg, warnings) = load();
      expect(cfg.defaultModel, 'bogus');
      expect(defaultModelFor(cfg).alias, kDefaultProfile.profile.alias);
      expect(warnings.single, contains('default_model "bogus"'));
    });
  });
}
