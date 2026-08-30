import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/cli/voice_config.dart';
import 'package:tts_narrator_core/src/narration/cost.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';

void main() {
  group('loadVoiceConfig', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tts_config_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    String write(String contents) {
      final f = File('${dir.path}/voice_config.json')
        ..writeAsStringSync(contents);
      return f.path;
    }

    test('missing file yields an empty config', () {
      final cfg = loadVoiceConfig('${dir.path}/nope.json');
      expect(cfg.isEmpty, isTrue);
      expect(cfg.defaultProvider, isNull);
      expect(cfg.providers, isEmpty);
      expect(cfg.aliases, isEmpty);
    });

    test('parses defaults, pricing and per-model aliases', () {
      final path = write(
        jsonSample(
          defaults: {'fish': 'Narrator'},
          pricing: {
            'kokoro': {'usd_per_m_chars': 0.62},
          },
          voices: {
            'fish': {'Narrator': 'hex1'},
            'kokoro': {'Emma': 'bf_emma'},
          },
        ),
      );
      final cfg = loadVoiceConfig(path);
      expect(cfg.defaults['fish'], 'Narrator');
      expect(cfg.pricing['kokoro']?.usdPerMChars, 0.62);
      expect(cfg.aliases['fish']?['Narrator'], 'hex1');
      expect(cfg.aliases['kokoro']?['Emma'], 'bf_emma');
    });

    test('parses the models block into request profiles', () {
      final path = write('''{
  "models": {
    "fish": {"id": "fish-audio/s2.1-pro-free", "format": "mp3"},
    "gemini": {"id": "google/gemini-3.1-flash-tts-preview",
               "format": "pcm", "sample_rate": 24000, "prompt_style": true},
    "kokoro": {"id": "hexgrad/kokoro-82m", "format": "mp3"}
  }
}''');
      final cfg = loadVoiceConfig(path);
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
      final path = write('''{"models": {"x": {"id": "a/b"}}}''');
      final cfg = loadVoiceConfig(path);
      final m = cfg.models['x']!;
      expect(m.format, 'mp3');
      expect(m.promptStyle, isFalse);
      expect(m.sendsVoiceField, isTrue);
      expect(m.sampleRate, isNull);
    });

    test('rejects a model entry with no id', () {
      final path = write('{"models": {"x": {"format": "mp3"}}}');
      expect(() => loadVoiceConfig(path), throwsA(isA<VoiceConfigError>()));
    });

    test('accepts a file with no models, providers, or voices', () {
      final path = write('{"voices": {}}');
      final cfg = loadVoiceConfig(path);
      expect(cfg.isEmpty, isTrue);
    });

    test(r'parses default_provider and the providers block verbatim', () {
      final path = write('''{
  "default_provider": "openrouter",
  "providers": {
    "openrouter": { "OPENROUTER_API_KEY": "\${OPENROUTER_API_KEY}" }
  }
}''');
      final cfg = loadVoiceConfig(path);
      expect(cfg.defaultProvider, 'openrouter');
      // The `${...}` env reference is preserved as a literal, not resolved.
      expect(cfg.providers, {
        'openrouter': {'OPENROUTER_API_KEY': r'${OPENROUTER_API_KEY}'},
      });
    });

    test('rejects a non-string default_provider', () {
      final path = write('{"default_provider": 42}');
      expect(() => loadVoiceConfig(path), throwsA(isA<VoiceConfigError>()));
    });

    test('rejects a non-object providers entry', () {
      final path = write('{"providers": {"openrouter": "sk-or"}}');
      expect(() => loadVoiceConfig(path), throwsA(isA<VoiceConfigError>()));
    });

    test('rejects a non-string value inside a providers entry', () {
      final path = write('{"providers": {"openrouter": {"KEY": 42}}}');
      expect(() => loadVoiceConfig(path), throwsA(isA<VoiceConfigError>()));
    });

    test(
      'parses models entry provider, defaulting to the compiled openrouter',
      () {
        final explicit = write(
          '{"models": {"gemini": {"id": "a/b", "provider": "google"}}}',
        );
        expect(loadVoiceConfig(explicit).models['gemini']?.provider, 'google');

        final implicit = write('{"models": {"fish": {"id": "a/b"}}}');
        expect(
          loadVoiceConfig(implicit).models['fish']?.provider,
          'openrouter',
        );
      },
    );

    test('rejects a non-string models provider', () {
      final path = write('{"models": {"x": {"id": "a/b", "provider": 7}}}');
      expect(() => loadVoiceConfig(path), throwsA(isA<VoiceConfigError>()));
    });

    test('default_provider folds into models without an explicit provider', () {
      final folded = write('''{
  "default_provider": "google",
  "models": {
    "implicit": {"id": "a/b"},
    "explicit": {"id": "c/d", "provider": "openrouter"}
  }
}''');
      final cfg = loadVoiceConfig(folded);
      // Implicit inherits the default; explicit wins.
      expect(cfg.models['implicit']?.provider, 'google');
      expect(cfg.models['explicit']?.provider, 'openrouter');
    });

    test('throws VoiceConfigError on malformed JSON', () {
      final path = write('{not json');
      expect(() => loadVoiceConfig(path), throwsA(isA<VoiceConfigError>()));
    });

    test('throws VoiceConfigError on non-object top level', () {
      final path = write('[1,2,3]');
      expect(() => loadVoiceConfig(path), throwsA(isA<VoiceConfigError>()));
    });

    test('ignores non-string voice id values, keeps the model key only if non-empty', () {
      final path = write(
        '''{"voices": {"fish": {"A": "id1", "B": 42, "C": ""}}}''',
      );
      final cfg = loadVoiceConfig(path);
      expect(cfg.aliases['fish']?['A'], 'id1');
      expect(cfg.aliases['fish']?.containsKey('B'), isFalse);
      expect(cfg.aliases['fish']?.containsKey('C'), isFalse);
    });
  });

  group('effectiveModels', () {
    test('with an empty config, only the fish bootstrap exists', () {
      final models = effectiveModels(const VoiceConfig());
      expect(models, hasLength(1));
      expect(models.single.alias, kDefaultProfile.profile.alias);
      expect(models.single.id, kDefaultProfile.profile.id);
    });

    test('config models extend the set with new providers', () {
      final cfg = VoiceConfig(
        models: {
          'gemini': const TtsModelProfile(
            alias: 'gemini',
            id: 'google/gemini-3.1-flash-tts-preview',
            format: 'pcm',
          ),
          'kokoro': const TtsModelProfile(
            alias: 'kokoro',
            id: 'hexgrad/kokoro-82m',
            format: 'mp3',
          ),
        },
      );
      final models = effectiveModels(cfg);
      expect(models.map((m) => m.alias).toList(), ['fish', 'gemini', 'kokoro']);
    });

    test('a config model overrides the fish bootstrap by alias', () {
      final cfg = VoiceConfig(
        models: {
          'fish': const TtsModelProfile(
            alias: 'fish',
            id: 'fish-audio/other-free',
            format: 'mp3',
          ),
        },
      );
      final models = effectiveModels(cfg);
      expect(models, hasLength(1));
      expect(models.single.id, 'fish-audio/other-free');
    });
  });

  group('profileFor', () {
    test('resolves a config alias or full id', () {
      final cfg = VoiceConfig(
        models: {
          'gemini': const TtsModelProfile(
            alias: 'gemini',
            id: 'google/gemini-3.1-flash-tts-preview',
            format: 'pcm',
          ),
        },
      );
      expect(
        profileFor('gemini', cfg)?.id,
        'google/gemini-3.1-flash-tts-preview',
      );
      expect(
        profileFor('google/gemini-3.1-flash-tts-preview', cfg)?.alias,
        'gemini',
      );
    });

    test('fish bootstraps in with an empty config', () {
      expect(profileFor('fish', const VoiceConfig()), isNotNull);
    });

    test('returns null for unknown names', () {
      expect(profileFor('bogus', const VoiceConfig()), isNull);
    });
  });

  group('resolveVoice', () {
    final cfg = VoiceConfig(
      aliases: {
        'fish': {'British Female Narrator (good)': '89f41ea'},
        'kokoro': {'Emma': 'bf_emma'},
      },
    );

    test('resolves an alias to its raw id and keeps the label', () {
      final (id, label) = cfg.resolveVoice(
        'fish',
        'British Female Narrator (good)',
      );
      expect(id, '89f41ea');
      expect(label, 'British Female Narrator (good)');
    });

    test('passes unknown values through unchanged', () {
      final (id, label) = cfg.resolveVoice(
        'fish',
        '2fd511bd06904a21a971c6551dfb853a',
      );
      expect(id, '2fd511bd06904a21a971c6551dfb853a');
      expect(label, '2fd511bd06904a21a971c6551dfb853a');
    });

    test('is isolated per model', () {
      final (id, _) = cfg.resolveVoice(
        'kokoro',
        'British Female Narrator (good)',
      );
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

  group('defaultVoiceFor', () {
    test('uses the configured default label', () {
      final cfg = VoiceConfig(
        defaults: const {'kokoro': 'Emma'},
        aliases: const {
          'kokoro': {'Emma': 'bf_emma'},
        },
      );
      final (id, label) = defaultVoiceFor(
        const TtsModelProfile(alias: 'kokoro', id: 'hexgrad/kokoro-82m'),
        cfg,
      );
      expect(id, 'bf_emma');
      expect(label, 'Emma');
    });

    test('fish falls back to the compiled bootstrap voice', () {
      final (id, label) = defaultVoiceFor(
        kDefaultProfile.profile,
        const VoiceConfig(),
      );
      expect(id, kDefaultProfile.voice);
      expect(label, kDefaultProfile.voiceLabel);
    });

    test('throws when a model has no default configured', () {
      expect(
        () => defaultVoiceFor(
          const TtsModelProfile(
            alias: 'gemini',
            id: 'google/gemini-3.1-flash-tts-preview',
          ),
          const VoiceConfig(),
        ),
        throwsA(isA<VoiceConfigError>()),
      );
    });
  });

  group('voiceEntries', () {
    test('fish includes its compiled default voice, no aliases', () {
      final entries = voiceEntries(
        model: kDefaultProfile.profile,
        config: const VoiceConfig(),
      );
      expect(entries, hasLength(1));
      expect(entries.single.id, kDefaultProfile.voice);
      expect(entries.single.label, 'British Female Narrator');
      expect(entries.single.isAlias, isFalse);
    });

    test('a model without aliases or a config default yields no entries', () {
      final entries = voiceEntries(
        model: const TtsModelProfile(
          alias: 'gemini',
          id: 'google/gemini-3.1-flash-tts-preview',
        ),
        config: const VoiceConfig(),
      );
      expect(entries, isEmpty);
    });

    test('includes aliases plus the default voice, deduped', () {
      final cfg = VoiceConfig(
        defaults: const {'fish': 'Narrator'},
        aliases: const {
          'fish': {'Narrator': 'hex1'},
        },
      );
      final entries = voiceEntries(model: kDefaultProfile.profile, config: cfg);
      expect(entries.where((e) => e.id == 'hex1'), hasLength(1));
      final alias = entries.firstWhere(
        (e) => e.id == 'hex1' && e.label == 'Narrator',
        orElse: () => throw 'missing',
      );
      expect(alias.isAlias, isTrue);
    });

    test('covers all effective models when none is given', () {
      final cfg = VoiceConfig(
        models: {
          'gemini': const TtsModelProfile(
            alias: 'gemini',
            id: 'google/gemini-3.1-flash-tts-preview',
            format: 'pcm',
          ),
        },
        aliases: const {
          'gemini': {'Charon': 'Charon'},
        },
      );
      final entries = voiceEntries(config: cfg);
      expect(
        entries.map((e) => e.model).toSet(),
        containsAll(['fish', 'gemini']),
      );
    });
  });

  group('writeVoiceConfig', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tts_config_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('round-trips default_provider, providers, models, defaults, pricing and aliases', () {
      final path = '${dir.path}/write_test/voice_config.json';
      writeVoiceConfig(
        path,
        VoiceConfig(
          defaultProvider: 'openrouter',
          providers: const {
            'openrouter': {'OPENROUTER_API_KEY': r'${OPENROUTER_API_KEY}'},
          },
          models: {
            'fish': kDefaultProfile.profile,
            'gemini': const TtsModelProfile(
              alias: 'gemini',
              id: 'google/gemini-3.1-flash-tts-preview',
              format: 'pcm',
              sampleRate: 24000,
              promptStyle: true,
            ),
          },
          defaults: const {'fish': 'Narrator'},
          pricing: {'kokoro': const AudioPricing(usdPerMChars: 0.62)},
          aliases: {
            'fish': {'Narrator': 'hex1'},
            'kokoro': {'Emma': 'bf_emma'},
          },
        ),
      );
      final cfg = loadVoiceConfig(path);
      expect(cfg.defaultProvider, 'openrouter');
      expect(cfg.providers['openrouter']?['OPENROUTER_API_KEY'],
          r'${OPENROUTER_API_KEY}');
      expect(cfg.models['gemini']?.id, 'google/gemini-3.1-flash-tts-preview');
      expect(cfg.models['gemini']?.sampleRate, 24000);
      expect(cfg.models['gemini']?.promptStyle, isTrue);
      expect(cfg.defaults['fish'], 'Narrator');
      expect(cfg.pricing['kokoro']?.usdPerMChars, 0.62);
      expect(cfg.aliases['fish']?['Narrator'], 'hex1');
      expect(cfg.aliases['kokoro']?['Emma'], 'bf_emma');
    });

    test('omits empty sections rather than writing nulls', () {
      final path = '${dir.path}/voice_config.json';
      writeVoiceConfig(path, const VoiceConfig());
      expect(File(path).readAsStringSync(), contains('{}'));
    });

    test('creates missing parent directories', () {
      final path = '${dir.path}/a/b/c/voice_config.json';
      writeVoiceConfig(path, const VoiceConfig(defaultProvider: 'openrouter'));
      expect(File(path).existsSync(), isTrue);
    });

    test('round-trips default_provider and the providers block verbatim', () {
      final path = '${dir.path}/voice_config.json';
      writeVoiceConfig(
        path,
        const VoiceConfig(
          defaultProvider: 'openrouter',
          providers: {
            'openrouter': {'OPENROUTER_API_KEY': r'${OPENROUTER_API_KEY}'},
          },
        ),
      );
      final cfg = loadVoiceConfig(path);
      expect(cfg.defaultProvider, 'openrouter');
      expect(
        cfg.providers['openrouter']?['OPENROUTER_API_KEY'],
        r'${OPENROUTER_API_KEY}',
      );
      // The env reference survives in the file, unresolved.
      expect(File(path).readAsStringSync(), contains(r'${OPENROUTER_API_KEY}'));
    });

    test('round-trips a per-model provider override', () {
      final path = '${dir.path}/voice_config.json';
      writeVoiceConfig(
        path,
        const VoiceConfig(
          models: {
            'gemini': TtsModelProfile(
              alias: 'gemini',
              id: 'a/b',
              provider: 'google',
            ),
          },
        ),
      );
      expect(loadVoiceConfig(path).models['gemini']?.provider, 'google');
    });

    test('preserves an explicit provider that differs from default_provider',
        () {
      final path = '${dir.path}/voice_config.json';
      writeVoiceConfig(
        path,
        const VoiceConfig(
          defaultProvider: 'google',
          providers: {'google': {'API_KEY': 'k'}, 'openrouter': {'API_KEY': 'o'}},
          models: {
            'gemini': TtsModelProfile(
              alias: 'gemini',
              id: 'a/b',
              provider: 'openrouter', // explicit override, != default_provider
            ),
          },
        ),
      );
      final raw = File(path).readAsStringSync();
      expect(raw, contains('"provider": "openrouter"'));
      expect(loadVoiceConfig(path).models['gemini']?.provider, 'openrouter');
    });

    test('elides a provider that merely repeats default_provider', () {
      final path = '${dir.path}/voice_config.json';
      writeVoiceConfig(
        path,
        const VoiceConfig(
          defaultProvider: 'google',
          models: {
            'gemini': TtsModelProfile(
              alias: 'gemini',
              id: 'a/b',
              provider: 'google',
            ),
          },
        ),
      );
      final raw = File(path).readAsStringSync();
      expect(raw, isNot(contains('"provider"')));
      expect(loadVoiceConfig(path).models['gemini']?.provider, 'google');
    });

    test('omits default_provider and providers when empty', () {
      final path = '${dir.path}/voice_config.json';
      writeVoiceConfig(path, const VoiceConfig());
      expect(File(path).readAsStringSync(), contains('{}'));

      writeVoiceConfig(path, const VoiceConfig(defaultProvider: 'openrouter'));
      final s = File(path).readAsStringSync();
      expect(s, contains('default_provider'));
      expect(s, isNot(contains('"providers"')));
    });

    test('throws VoiceConfigError when the path cannot be written', () {
      final path = '/dev/null/voice_config.json';
      expect(
        () => writeVoiceConfig(path, const VoiceConfig(defaultProvider: 'x')),
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

String jsonSample({
  Map<String, Map<String, String>> voices = const {},
  Map<String, String> defaults = const {},
  Map<String, Map<String, Object?>> pricing = const {},
}) {
  final out = <String, Object?>{};
  if (defaults.isNotEmpty) out['defaults'] = defaults;
  if (pricing.isNotEmpty) out['pricing'] = pricing;
  out['voices'] = voices;
  return const JsonEncoder().convert(out);
}
