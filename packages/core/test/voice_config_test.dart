import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/voice_config.dart';
import 'package:tts_narrator_core/src/config/voice_config_io.dart';
import 'package:tts_narrator_core/src/config/voice_config_queries.dart';
import 'package:tts_narrator_core/src/narration/audio_format.dart';

import 'support/config_fixture.dart';

void main() {
  group('loadVoiceConfig', () {
    late Directory dir;

    late ConfigFixture fx;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tts_config_test_');
      fx = ConfigFixture(dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    /// Writes a model file. Every model names the provider that serves it, which
    /// is what makes it available at all, so [provider] is written into the file
    /// rather than collected somewhere the model could disagree with.
    void writeModel(String alias, String contents, {String provider = 'alpha'}) {
      fx.writeModel(alias, _withProvider(contents, provider));
    }

    /// Publishes the marker and one provider, then loads. The marker names
    /// nothing, so a test that wants a model present writes the model file and
    /// the provider file it names.
    (VoiceConfig, List<String>) load({String provider = 'alpha'}) {
      fx.writeMarker();
      fx.writeProvider(
        provider,
        jsonEncode({
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

    test('defaults model fields apply when omitted', () {
      writeModel('x', '{"id": "a/b", "formats": ["wav"]}');
      final (cfg, _) = load();
      final m = cfg.models['x']!;
      expect(m.formats, const [TtsAudioFormat.wav]);
      expect(m.promptStyle, isFalse);
      expect(m.sendsVoiceField, isTrue);
      expect(m.displayName, isNull);
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
      // Matched on the whole rendered warning rather than a word inside it: a
      // bare `contains('null')` would settle for any warning merely mentioning
      // nullability, and pass for the wrong reason. Each is named exactly once
      // by skip, so a doubled-quoting bug in the name cannot hide here.
      const because =
          'is skipped: a voice id in a "voices" list must be a non-empty string.';
      expect(
        warnings,
        containsAll(<Matcher>[
          startsWith('Voice "42" in model "x" $because'),
          startsWith('Voice "" in model "x" $because'),
          startsWith('Voice "null" in model "x" $because'),
        ]),
      );
      expect(warnings, hasLength(3));
      expect(warnings.every((w) => w.contains('is skipped')), isTrue);
    });

    test('skips a model file with no id and reports a warning', () {
      writeModel('x', '{}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.first, contains('Skipped model "x"'));
      expect(warnings.first, contains('"id"'));
    });

    test('skips a malformed model file and keeps the rest loading', () {
      writeModel('good', '{"id": "a/b", "formats": ["wav"]}');
      fx.writeModel('bad', '{not json');
      final (cfg, warnings) = load();
      expect(cfg.models.keys, ['good']);
      expect(warnings.first, contains('Skipped model "bad"'));
    });

    test('an unrelated json file beside the marker is ignored silently', () {
      // The GUI config dir is also its application-support dir, so on Linux
      // `shared_preferences.json` lands beside the config. Nothing reads the
      // config root, so it must not raise a warning.
      writeModel('fish', '{"id": "a/b", "formats": ["wav"]}');
      File('${dir.path}${Platform.pathSeparator}shared_preferences.json')
          .writeAsStringSync('{"flutter.appearance": "system"}');
      final (cfg, warnings) = load();
      expect(cfg.models.keys, ['fish']);
      expect(warnings, isEmpty);
    });

    test('a json file in models/ that is not a model file is warned about', () {
      // `models/` is only ever read for models now, so a stray file there is a
      // mistake worth naming rather than something to pass over in silence.
      writeModel('fish', '{"id": "a/b", "formats": ["wav"]}');
      fx.writeModel('shared_preferences', '{"flutter.appearance": "system"}');
      final (cfg, warnings) = load();
      expect(cfg.models.keys, ['fish']);
      expect(warnings.single, contains('Skipped model "shared_preferences"'));
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

    group('the model to provider relation', () {
      test('stamps the provider each model file names', () {
        writeModel('gemini', '{"id": "a/b", "formats": ["wav"]}',
            provider: 'google');
        writeModel('fish', '{"id": "c/d", "formats": ["wav"]}',
            provider: 'alpha');
        fx.writeMarker();
        fx.writeProvider('google', '{"settings": {}}');
        fx.writeProvider('alpha', '{"settings": {}}');

        final (cfg, warnings) = rawLoad();
        expect(warnings, isEmpty);
        expect(cfg.models['gemini']?.provider, 'google');
        expect(cfg.models['fish']?.provider, 'alpha');
      });

      test('each provider lists the models that name it', () {
        writeModel('zebra', '{"id": "z/a", "formats": ["wav"]}');
        writeModel('alph', '{"id": "a/b", "formats": ["wav"]}');
        writeModel('mid', '{"id": "m/n", "formats": ["wav"]}',
            provider: 'beta');
        fx.writeMarker();
        fx.writeProvider('alpha', '{"settings": {}}');
        fx.writeProvider('beta', '{"settings": {}}');

        final (cfg, _) = rawLoad();
        expect(cfg.providers['alpha']?.models, ['alph', 'zebra']);
        expect(cfg.providers['beta']?.models, ['mid']);
      });

      test('a model naming a provider with no file on disk warns and drops', () {
        writeModel('x', '{"id": "a/b", "formats": ["wav"]}',
            provider: 'ghost');
        fx.writeMarker();
        final (cfg, warnings) = rawLoad();
        expect(cfg.models, isEmpty);
        expect(warnings.single, contains('ghost'));
      });

      test('a model naming no provider at all warns and drops', () {
        fx.writeModel('x', '{"id": "a/b", "formats": ["wav"]}');
        fx.writeMarker();
        fx.writeProvider('alpha', '{"settings": {}}');
        final (cfg, warnings) = rawLoad();
        expect(cfg.models, isEmpty);
        expect(warnings.single, contains('"provider"'));
      });

      test('a provider no model names is still loaded, with no models', () {
        fx.writeMarker();
        fx.writeProvider('alpha', '{"settings": {"base_url": "http://x"}}');
        final (cfg, warnings) = rawLoad();
        expect(warnings, isEmpty);
        expect(cfg.providers.keys, ['alpha']);
        expect(cfg.providers['alpha']?.models, isEmpty);
      });
    });
  });
}

/// Adds `"provider": <provider>` to the model JSON [contents], so a test can
/// write the model it is really about and still make it routable.
String _withProvider(String contents, String provider) {
  final decoded = jsonDecode(contents);
  if (decoded is! Map<String, dynamic>) return contents;
  return jsonEncode({...decoded, 'provider': provider});
}