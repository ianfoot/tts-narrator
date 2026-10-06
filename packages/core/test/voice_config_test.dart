import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/voice_config.dart';
import 'package:tts_narrator_core/src/config/voice_config_io.dart';
import 'package:tts_narrator_core/src/config/voice_config_queries.dart';
import 'package:tts_narrator_core/src/narration/audio_format.dart';

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
    (VoiceConfig, List<String>) load({String provider = 'alpha'}) {
      writeRegistry(
        jsonEncode({
          'providers': [provider],
        }),
      );
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
  "formats": ["mp3"],
  "prompt_style": true
}''');
      writeModel(
        'kokoro',
        '{"id": "hexgrad/kokoro-82m", "formats": ["wav", "mp3"]}',
      );
      writeModel(
        'fish',
        '{"id": "fish-audio/s2.1-pro-free", "formats": ["mp3"]}',
      );
      final (cfg, _) = load();
      expect(cfg.models, hasLength(3));
      expect(cfg.models['gemini']?.id, 'google/gemini-3.1-flash-tts-preview');
      expect(cfg.models['gemini']?.formats, const [TtsAudioFormat.mp3]);
      expect(cfg.models['gemini']?.promptStyle, isTrue);
      expect(cfg.models['gemini']?.sendsVoiceField, isTrue);
      expect(cfg.models['kokoro']?.formats, const [
        TtsAudioFormat.wav,
        TtsAudioFormat.mp3,
      ]);
      expect(cfg.models['fish']?.id, 'fish-audio/s2.1-pro-free');
    });

    test('defaults model fields apply when omitted', () {
      writeModel('x', '{"id": "a/b", "formats": ["wav"]}');
      final (cfg, _) = load();
      final m = cfg.models['x']!;
      expect(m.formats, const [TtsAudioFormat.wav]);
      expect(m.promptStyle, isFalse);
      expect(m.sendsVoiceField, isTrue);
    });

    test('parses an optional display_name into the profile', () {
      writeModel(
        'gemini',
        '{"id": "google/gemini-3.1-flash-tts-preview", "formats": ["wav"],'
            ' "display_name": "Gemini 3.1 Flash TTS"}',
      );
      final (cfg, _) = load();
      final m = cfg.models['gemini']!;
      expect(m.displayName, 'Gemini 3.1 Flash TTS');
    });

    test('display_name defaults to null when omitted', () {
      writeModel('x', '{"id": "a/b", "formats": ["wav"]}');
      final (cfg, _) = load();
      expect(cfg.models['x']!.displayName, isNull);
    });

    test('a non-string display_name skips the model with a warning', () {
      writeModel('x', '{"id": "a/b", "formats": ["wav"], "display_name": 7}');
      final (cfg, warnings) = load();
      expect(cfg.models.containsKey('x'), isFalse);
      expect(warnings.join('\n'), contains('display_name'));
    });

    test('parses per-model default_voice, pricing and voices', () {
      writeModel('fish', '''
{
  "id": "fish-audio/s2.1-pro-free",
  "formats": ["mp3"],
  "default_voice": "Narrator",
  "pricing": {"usd_per_m_chars": 0.62},
  "voices": {"Narrator": "hex1", "Emma": "bf_emma"}
}''');
      writeModel(
        'kokoro',
        '{"id": "hexgrad/kokoro-82m", "formats": ["wav"],'
            ' "voices": {"Emma": "bf_emma"}}',
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
  "formats": ["wav"],
  "voices": {
    "Emma": {"id": "bf_emma", "gender": "female"},
    "Daniel": {"id": "bm_daniel", "gender": "male"},
    "Fable": {"id": "bm_fable"}
  }
}
''');
      writeModel('gemini', '{"id": "a/b", "formats": ["wav"]}');
      final (cfg, _) = load();
      expect(cfg.voices['kokoro']?['Emma']?.id, 'bf_emma');
      expect(cfg.voices['kokoro']?['Emma']?.gender, VoiceGender.female);
      expect(cfg.voices['kokoro']?['Daniel']?.gender, VoiceGender.male);
      // Untyped entries carry an id but no gender tag.
      expect(cfg.voices['kokoro']?['Fable']?.gender, isNull);
      // Untagged models carry no entries at all.
      expect(cfg.voices.containsKey('gemini'), isFalse);
    });

    test('accepts a voice entry written as a string shorthand', () {
      writeModel('x', '''
{
  "id": "a/b",
  "formats": ["wav"],
  "voices": {"A": "id1", "B": 42, "C": ""}
}
''');
      final (cfg, warnings) = load();
      expect(cfg.voices['x']?['A']?.id, 'id1');
      expect(cfg.voices['x']?['A']?.gender, isNull);
      // Malformed entries are skipped, and reported.
      expect(cfg.voices['x']?.containsKey('B'), isFalse);
      expect(cfg.voices['x']?.containsKey('C'), isFalse);
      expect(
        warnings.singleWhere((w) => w.contains('"B"')),
        'Voice "B" in model "x" is skipped: it is neither a voice id nor a '
        'voice object.',
      );
      expect(
        warnings.singleWhere((w) => w.contains('"C"')),
        'Voice "C" in model "x" is skipped: its voice id is empty.',
      );
    });

    test('skips an entry whose id is unusable, and says so', () {
      writeModel('x', '''
{
  "id": "a/b",
  "formats": ["wav"],
  "voices": {
    "A": {"id": "ok1", "gender": "female"},
    "B": {"id": ""},
    "C": {"gender": "male"},
    "D": {"id": 42},
    "E": {"id": "ok2", "gender": "soprano"},
    "F": {"id": "ok3", "gender": "Male"},
    "G": {"iid": "ok4"},
    "H": {"iid": "ok5", "jawn": true}
  }
}
''');
      final (cfg, warnings) = load();
      final voices = cfg.voices['x']!;
      expect(voices['A']?.gender, VoiceGender.female);
      // An entry keyed by its own id and only annotated stays a voice.
      expect(voices['C']?.id, 'C');
      expect(voices['C']?.gender, VoiceGender.male);
      // An unusable id is dropped: the key would then be an alias sent to the
      // provider as a voice id, narrating in the wrong voice instead of here.
      expect(voices.containsKey('B'), isFalse);
      expect(voices.containsKey('D'), isFalse);
      // So is an entry made only of fields this schema does not define, which is
      // what a mistyped id looks like.
      expect(voices.containsKey('G'), isFalse);
      expect(voices.containsKey('H'), isFalse);
      expect(
        warnings.singleWhere((w) => w.contains('"G"')),
        'Voice "G" in model "x" is skipped: it names no "id" and its only field '
        'is "iid", which this config schema does not define.',
      );
      expect(
        warnings.singleWhere((w) => w.contains('"H"')),
        'Voice "H" in model "x" is skipped: it names no "id" and its only '
        'fields are "iid", "jawn", which this config schema does not define.',
      );
      for (final key in ['B', 'D']) {
        expect(
          warnings.singleWhere((w) => w.contains('"$key"')),
          'Voice "$key" in model "x" is skipped: its "id" is not a non-empty '
          'string.',
        );
      }
      // Unrecognized gender strings are dropped, the voice kept.
      expect(voices['E']?.id, 'ok2');
      expect(voices['E']?.gender, isNull);
      // Case-insensitive gender parsing.
      expect(voices['F']?.gender, VoiceGender.male);
      // Only the four unusable entries are reported.
      expect(warnings, hasLength(4));
    });

    test('reads a voice name and keeps it out of the id', () {
      writeModel('x', '''
{
  "id": "a/b",
  "formats": ["wav"],
  "voices": {
    "bf_emma": {"name": "Emma"},
    "am_santa": {"name": "Santa"},
    "em_santa": {"name": "Santa"},
    "plain": {},
    "blank": {"name": "   "},
    "wrong": {"name": 42}
  }
}
''');
      final (cfg, _) = load();
      final voices = cfg.voices['x']!;
      expect(voices['bf_emma']?.id, 'bf_emma');
      expect(voices['bf_emma']?.name, 'Emma');
      // Duplicate names are fine; the keys are what must be unique.
      expect(voices['am_santa']?.name, 'Santa');
      expect(voices['em_santa']?.name, 'Santa');
      // A voice with no annotations is an empty entry, keyed by its own id.
      expect(voices['plain']?.id, 'plain');
      expect(voices['plain']?.name, isNull);
      expect(voices['blank']?.name, isNull);
      expect(voices['wrong']?.name, isNull);
    });

    test('rejects a voices block that is neither an object nor a list', () {
      writeModel('x', '{"id": "a/b", "formats": ["wav"], "voices": "female"}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.first, contains('"voices"'));
    });

    test('reads a bare list of voice ids, each its own key, id and label', () {
      writeModel(
        'x',
        '{"id": "a/b", "formats": ["wav"],'
            ' "voices": ["Charon", "Zephyr"]}',
      );
      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      final voices = cfg.voices['x']!;
      expect(voices.keys, ['Charon', 'Zephyr']);
      expect(voices['Charon']?.id, 'Charon');
      // No name and no gender: the list says nothing else about the voice, and
      // the picker reads `name ?? key`, so the key is the label either way.
      expect(voices['Charon']?.name, isNull);
      expect(voices['Zephyr']?.gender, isNull);
      expect(cfg.resolveVoice('x', 'Zephyr'), ('Zephyr', 'Zephyr'));
    });

    test('a bare list of ids still resolves a default_voice among them', () {
      writeModel(
        'x',
        '{"id": "a/b", "formats": ["wav"], "default_voice": "Puck",'
            ' "voices": ["Charon", "Puck"]}',
      );
      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      final model = cfg.models['x']!;
      expect(defaultVoiceFor(model, cfg), (
        'Puck',
        'Puck',
      ), reason: 'a list entry is key and id at once, so the default resolves');
    });

    test('rejects an empty list, which would offer no voices at all', () {
      writeModel('x', '{"id": "a/b", "formats": ["wav"], "voices": []}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.first, contains('empty list'));
    });

    test('skips a list entry that is not a non-empty string', () {
      // One unusable entry must not cost the model, the same as a bad entry in
      // the object form, so this is a warning rather than a rejected file.
      writeModel(
        'x',
        '{"id": "a/b", "formats": ["wav"],'
            ' "voices": ["Charon", 42, "", null, "Zephyr"]}',
      );
      final (cfg, warnings) = load();
      expect(cfg.voices['x']?.keys, ['Charon', 'Zephyr']);
      expect(warnings.where((w) => w.contains('"42"')), hasLength(1));
      expect(warnings.where((w) => w.contains('null')), hasLength(1));
      expect(warnings.every((w) => w.contains('is skipped')), isTrue);
    });

    test('skips a model file with no id and reports a warning', () {
      writeModel('x', '{}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.first, contains('Skipped model "x"'));
    });

    test('skips a malformed model file and keeps the rest loading', () {
      writeModel('good', '{"id": "a/b", "formats": ["wav"]}');
      writeModel('bad', '{not json');
      final (cfg, warnings) = load();
      expect(cfg.models.keys, ['good']);
      expect(warnings.first, contains('Skipped model "bad"'));
    });

    test('an unrelated json file beside the models is ignored silently', () {
      // The GUI config dir is also its application-support dir, so on Linux
      // `shared_preferences.json` lands beside the config. No provider names
      // it, so it must not raise a warning.
      writeModel('fish', '{"id": "a/b", "formats": ["wav"]}');
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
      writeModel('x', '{}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.first, contains('Skipped model "x"'));
      expect(warnings.first, contains('"id"'));
    });

    test('a wrong-typed model field is skipped with a warning', () {
      writeModel('x', '{"id": "a/b", "formats": "mp3"}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.first, contains('Skipped model "x"'));
      expect(warnings.first, contains('"formats"'));
    });

    test('an unmodelled key such as a stale sample_rate is ignored', () {
      // The rate is a property of the WAV the provider returns and the app
      // carries that container through untouched, so the key has nothing left
      // to configure and a config still carrying it must load rather than fail.
      writeModel(
        'x',
        '{"id": "a/b", "formats": ["wav"], "sample_rate": 24000}',
      );
      final (cfg, warnings) = load();
      expect(cfg.models['x']?.formats, const [TtsAudioFormat.wav]);
      expect(warnings, isEmpty);
    });

    test('model files are read in sorted filename order', () {
      writeModel('zebra', '{"id": "z/a", "formats": ["wav"]}');
      writeModel('alph', '{"id": "a/b", "formats": ["wav"]}');
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
        writeRegistry('{"providers": ["alpha", "beta"]}');
        writeProvider('alpha', '{"models": ["fish"], "settings": {}}');
        writeProvider('beta', '{"models": [], "settings": {}}');
        final (cfg, _) = rawLoad();
        expect(cfg.providers.keys, ['alpha', 'beta']);
        expect(cfg.defaultProvider?.name, 'alpha');
      });

      test(r'keeps a $VAR env reference as a literal', () {
        writeRegistry('{"providers": ["alpha"]}');
        writeProvider(
          'alpha',
          '{"models": [], "settings": '
              '{"VENDOR_API_KEY": "\${VENDOR_API_KEY}"}}',
        );
        final (cfg, _) = rawLoad();
        expect(
          cfg.providers['alpha']!.settings['VENDOR_API_KEY'],
          r'${VENDOR_API_KEY}',
        );
      });

      test('rejects a non-list providers entry', () {
        writeRegistry('{"providers": {"alpha": {}}}');
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
        writeModel(
          'gemini',
          '{"id": "a/b", "formats": ["wav"]}',
          claimedByProvider: false,
        );
        writeModel(
          'fish',
          '{"id": "c/d", "formats": ["wav"]}',
          claimedByProvider: false,
        );
        writeRegistry('{"providers": ["google", "alpha"]}');
        writeProvider('google', '{"models": ["gemini"], "settings": {}}');
        writeProvider('alpha', '{"models": ["fish"], "settings": {}}');

        final (cfg, warnings) = rawLoad();
        expect(warnings, isEmpty);
        expect(cfg.models['gemini']?.provider, 'google');
        expect(cfg.models['fish']?.provider, 'alpha');
      });

      test('a model no provider names is skipped without a warning', () {
        writeModel(
          'x',
          '{"id": "a/b", "formats": ["wav"]}',
          claimedByProvider: false,
        );
        writeRegistry('{"providers": ["alpha"]}');
        writeProvider('alpha', '{"models": [], "settings": {}}');

        final (cfg, warnings) = rawLoad();
        expect(cfg.models, isEmpty);
        expect(warnings, isEmpty);
      });

      test(
        'a provider file absent from the registry is ignored with a warning',
        () {
          writeRegistry('{"providers": ["alpha"]}');
          writeProvider('alpha', '{"models": [], "settings": {}}');
          writeProvider('stray', '{"models": [], "settings": {}}');

          final (cfg, warnings) = rawLoad();
          expect(cfg.providers.containsKey('stray'), isFalse);
          expect(warnings.single, contains('stray.json'));
        },
      );

      test('a registered provider with no file on disk warns', () {
        writeRegistry('{"providers": ["alpha"]}');
        final (cfg, warnings) = rawLoad();
        expect(cfg.providers, isEmpty);
        expect(warnings.first, contains('providers/alpha.json is missing'));
      });

      test('a provider naming a model that never loaded warns', () {
        writeRegistry('{"providers": ["alpha"]}');
        writeProvider('alpha', '{"models": ["gone"], "settings": {}}');

        final (_, warnings) = rawLoad();
        expect(warnings.single, contains('gone'));
      });
    });

    group('the default model', () {
      test('is the first model of the first registered provider', () {
        writeModel(
          'kokoro',
          '{"id": "a/b", "formats": ["wav"]}',
          claimedByProvider: false,
        );
        writeModel(
          'fish',
          '{"id": "c/d", "formats": ["wav"]}',
          claimedByProvider: false,
        );
        writeRegistry('{"providers": ["alpha", "google"]}');
        writeProvider('alpha', '{"models": ["kokoro"], "settings": {}}');
        writeProvider('google', '{"models": ["fish"], "settings": {}}');

        final (cfg, _) = rawLoad();
        expect(defaultModelFor(cfg)?.alias, 'kokoro');
      });
    });
  });
}
