import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/voice_config.dart';
import 'package:tts_narrator_core/src/config/voice_config_queries.dart';
import 'package:tts_narrator_core/src/config/voice_config_io.dart';

void main() {
  group('loadVoiceConfig', () {
    late Directory dir;
    final claimed = <String>[];

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tts_config_test_');
      claimed.clear();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    String at(String subdir, String file) =>
        '${dir.path}${Platform.pathSeparator}$subdir'
        '${Platform.pathSeparator}$file';

    void writeRegistry(String contents) =>
        File('${dir.path}${Platform.pathSeparator}$kVoiceConfigRegistryName')
            .writeAsStringSync(contents);

    void writeProvider(String name, String contents) {
      final file = File(at(kVoiceConfigProvidersDir, '$name.json'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    void writeModel(
      String alias,
      String contents, {
      bool claimedByProvider = true,
    }) {
      final file = File(at(kVoiceConfigModelsDir, '$alias.json'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
      if (claimedByProvider) claimed.add(alias);
    }

    /// Publishes the registry and a single provider claiming every model
    /// written so far, then loads. Model files only exist to a provider that
    /// names them, so the registry has to agree with the fixture.
    (VoiceConfig, List<String>) load({String provider = 'openrouter'}) {
      writeRegistry(jsonEncode({'providers': [provider]}));
      writeProvider(
        provider,
        jsonEncode({
          'models': claimed,
          'settings': {'base_url': 'https://example.invalid/v1'},
        }),
      );
      return loadVoiceConfig(dir.path);
    }

    (VoiceConfig, List<String>) rawLoad() => loadVoiceConfig(dir.path);

    test('missing directory yields an empty config and no warnings', () {
      final (cfg, warnings) = loadVoiceConfig('${dir.path}/nope');
      expect(cfg.isEmpty, isTrue);
      expect(cfg.providers, isEmpty);
      expect(cfg.voices, isEmpty);
      expect(warnings, isEmpty);
    });

    test('parses per-model files into request profiles', () {
      writeModel('gemini', '''{
  "id": "google/gemini-3.1-flash-tts-preview",
  "format": "pcm",
  "sample_rate": 24000,
  "prompt_style": true
}''');
      writeModel('kokoro', '{"id": "hexgrad/kokoro-82m", "format": "mp3"}');
      writeModel('fish', '{"id": "fish-audio/s2.1-pro-free", "format": "mp3"}');
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
      writeModel('x', '{"id": "a/b"}');
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
        '{"id": "google/gemini-3.1-flash-tts-preview", "display_name": "Gemini 3.1 Flash TTS"}',
      );
      final (cfg, _) = load();
      final m = cfg.models['gemini']!;
      expect(m.displayName, 'Gemini 3.1 Flash TTS');
    });

    test('display_name defaults to null when omitted', () {
      writeModel('x', '{"id": "a/b"}');
      final (cfg, _) = load();
      expect(cfg.models['x']!.displayName, isNull);
    });

    test('a non-string display_name skips the model with a warning', () {
      writeModel('x', '{"id": "a/b", "display_name": 7}');
      final (cfg, warnings) = load();
      expect(cfg.models.containsKey('x'), isFalse);
      expect(warnings.join('\n'), contains('display_name'));
    });

    test('parses per-model default_voice, pricing and voices', () {
      writeModel('fish', '''
{
  "id": "fish-audio/s2.1-pro-free",
  "default_voice": "Narrator",
  "pricing": {"usd_per_m_chars": 0.62},
  "voices": {"Narrator": "hex1", "Emma": "bf_emma"}
}''');
      writeModel(
        'kokoro',
        '{"id": "hexgrad/kokoro-82m", "voices": {"Emma": "bf_emma"}}',
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
  "voices": {
    "Emma": {"id": "bf_emma", "gender": "female"},
    "Daniel": {"id": "bm_daniel", "gender": "male"},
    "Fable": {"id": "bm_fable"}
  }
}
''');
      writeModel('gemini', '{"id": "a/b"}');
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
      writeModel('x', '{"id": "a/b", "voices": ["female"]}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.first, contains('"voices"'));
    });

    test('skips a model file with no id and reports a warning', () {
      writeModel('x', '{"format": "mp3"}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.first, contains('Skipped model "x"'));
    });

    test('skips a malformed model file and keeps the rest loading', () {
      writeModel('good', '{"id": "a/b"}');
      writeModel('bad', '{not json');
      final (cfg, warnings) = load();
      expect(cfg.models.keys, ['good']);
      expect(warnings.first, contains('Skipped model "bad"'));
    });

    test('an unrelated json file beside the models is ignored silently', () {
      // The GUI config dir is also its application-support dir, so on Linux
      // `shared_preferences.json` lands beside the config. No provider names
      // it, so it must not raise a warning.
      writeModel('fish', '{"id": "a/b"}');
      writeModel(
        'shared_preferences',
        '{"flutter.appearance": "system"}',
        claimedByProvider: false,
      );
      final (cfg, warnings) = load();
      expect(cfg.models.keys, ['fish']);
      expect(warnings, isEmpty);
    });

    test('a non-object json file beside the models is ignored silently', () {
      writeModel('whatever', '[1, 2, 3]', claimedByProvider: false);
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings, isEmpty);
    });

    test('a json file sharing no key with the model schema is ignored', () {
      // Being named by a provider is the only candidacy test now, so this one
      // is judged on that rather than on which keys it happens to carry.
      writeModel('x', '{"totally": "unrelated"}', claimedByProvider: false);
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings, isEmpty);
    });

    test('a model file missing only its id still warns', () {
      writeModel('x', '{"format": "mp3"}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.first, contains('Skipped model "x"'));
      expect(warnings.first, contains('"id"'));
    });

    test('a wrong-typed model field is skipped with a warning', () {
      writeModel('x', '{"id": "a/b", "sample_rate": "lots"}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.first, contains('Skipped model "x"'));
    });

    test('model files are read in sorted filename order', () {
      writeModel('zebra', '{"id": "z/a"}');
      writeModel('alph', '{"id": "a/b"}');
      final (cfg, _) = load();
      expect(cfg.models.keys.toList(), ['alph', 'zebra']);
    });

    test(
      'accepts a directory with only an empty config.json and no models',
      () {
        writeRegistry('{}');
        final (cfg, _) = rawLoad();
        expect(cfg.isEmpty, isTrue);
      },
    );

    group('the provider registry', () {
      test('parses the provider names in order', () {
        writeRegistry('{"providers": ["openrouter", "mlx_audio"]}');
        writeProvider('openrouter', '{"models": ["fish"], "settings": {}}');
        writeProvider('mlx_audio', '{"models": [], "settings": {}}');
        final (cfg, _) = rawLoad();
        expect(cfg.providers.keys, ['openrouter', 'mlx_audio']);
        expect(cfg.defaultProvider?.name, 'openrouter');
      });

      test(r'keeps a $VAR env reference as a literal', () {
        writeRegistry('{"providers": ["openrouter"]}');
        writeProvider(
          'openrouter',
          '{"models": [], "settings": '
              '{"OPENROUTER_API_KEY": "\${OPENROUTER_API_KEY}"}}',
        );
        final (cfg, _) = rawLoad();
        expect(
          cfg.providers['openrouter']!.settings['OPENROUTER_API_KEY'],
          r'${OPENROUTER_API_KEY}',
        );
      });

      test('rejects a non-list providers entry', () {
        writeRegistry('{"providers": {"openrouter": {}}}');
        expect(rawLoad, throwsA(isA<VoiceConfigurationError>()));
      });

      test('rejects a non-string provider name', () {
        writeRegistry('{"providers": [42]}');
        expect(rawLoad, throwsA(isA<VoiceConfigurationError>()));
      });

      test('rejects a blank provider name', () {
        writeRegistry('{"providers": ["  "]}');
        expect(rawLoad, throwsA(isA<VoiceConfigurationError>()));
      });

      test('rejects malformed config.json loudly', () {
        writeRegistry('{not json');
        expect(rawLoad, throwsA(isA<VoiceConfigurationError>()));
      });

      test('rejects a non-object top level in config.json', () {
        writeRegistry('[1,2,3]');
        expect(rawLoad, throwsA(isA<VoiceConfigurationError>()));
      });

      test('an empty registry leaves the config empty', () {
        writeRegistry('{"providers": []}');
        final (cfg, warnings) = rawLoad();
        expect(cfg.isEmpty, isTrue);
        expect(warnings, isEmpty);
      });
    });

    group('the model to provider relation', () {
      test('stamps the claiming provider onto each profile', () {
        writeModel('gemini', '{"id": "a/b"}', claimedByProvider: false);
        writeModel('fish', '{"id": "c/d"}', claimedByProvider: false);
        writeRegistry('{"providers": ["google", "openrouter"]}');
        writeProvider('google', '{"models": ["gemini"], "settings": {}}');
        writeProvider('openrouter', '{"models": ["fish"], "settings": {}}');

        final (cfg, warnings) = rawLoad();
        expect(warnings, isEmpty);
        expect(cfg.models['gemini']?.provider, 'google');
        expect(cfg.models['fish']?.provider, 'openrouter');
      });

      test('a model no provider names is skipped without a warning', () {
        writeModel('x', '{"id": "a/b"}', claimedByProvider: false);
        writeRegistry('{"providers": ["openrouter"]}');
        writeProvider('openrouter', '{"models": [], "settings": {}}');

        final (cfg, warnings) = rawLoad();
        expect(cfg.models, isEmpty);
        expect(warnings, isEmpty);
      });

      test('a provider file absent from the registry is ignored with a warning',
          () {
        writeRegistry('{"providers": ["openrouter"]}');
        writeProvider('openrouter', '{"models": [], "settings": {}}');
        writeProvider('stray', '{"models": [], "settings": {}}');

        final (cfg, warnings) = rawLoad();
        expect(cfg.providers.containsKey('stray'), isFalse);
        expect(warnings.single, contains('stray.json'));
      });

      test('a registered provider with no file on disk warns', () {
        writeRegistry('{"providers": ["openrouter"]}');
        final (cfg, warnings) = rawLoad();
        expect(cfg.providers, isEmpty);
        expect(warnings.first, contains('providers/openrouter.json is missing'));
      });

      test('a provider naming a model that never loaded warns', () {
        writeRegistry('{"providers": ["openrouter"]}');
        writeProvider('openrouter', '{"models": ["gone"], "settings": {}}');

        final (_, warnings) = rawLoad();
        expect(warnings.single, contains('gone'));
      });
    });

    group('the default model', () {
      test('is the first model of the first registered provider', () {
        writeModel('kokoro', '{"id": "a/b"}', claimedByProvider: false);
        writeModel('fish', '{"id": "c/d"}', claimedByProvider: false);
        writeRegistry('{"providers": ["openrouter", "google"]}');
        writeProvider('openrouter', '{"models": ["kokoro"], "settings": {}}');
        writeProvider('google', '{"models": ["fish"], "settings": {}}');

        final (cfg, _) = rawLoad();
        expect(defaultModelFor(cfg)?.alias, 'kokoro');
      });
    });
  });
}
