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
      expect(cfg.aliases, isEmpty);
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
      writeModel('kokoro', '{"id": "hexgrad/kokoro-82m", "provider": "openrouter", "format": "mp3"}');
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

    test('parses per-model default_voice, pricing and voices', () {
      writeModel('fish', '''
{
  "id": "fish-audio/s2.1-pro-free",
  "provider": "openrouter",
  "default_voice": "Narrator",
  "pricing": {"usd_per_m_chars": 0.62},
  "voices": {"Narrator": "hex1", "Emma": "bf_emma"}
}''');
      writeModel('kokoro', '{"id": "hexgrad/kokoro-82m", "provider": "openrouter", "voices": {"Emma": "bf_emma"}}');
      final (cfg, _) = load();
      expect(cfg.defaults['fish'], 'Narrator');
      expect(cfg.pricing['fish']?.usdPerMChars, 0.62);
      expect(cfg.aliases['fish']?['Narrator'], 'hex1');
      expect(cfg.aliases['fish']?['Emma'], 'bf_emma');
      expect(cfg.aliases['kokoro']?['Emma'], 'bf_emma');
    });

    test('ignores non-string voice id values, keeps the model key only if non-empty',
        () {
      writeModel('fish', '''
{"id": "a/b", "provider": "openrouter", "voices": {"A": "id1", "B": 42, "C": ""}}
''');
      final (cfg, _) = load();
      expect(cfg.aliases['fish']?['A'], 'id1');
      expect(cfg.aliases['fish']?.containsKey('B'), isFalse);
      expect(cfg.aliases['fish']?.containsKey('C'), isFalse);
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

    test('accepts a directory with only an empty config.json and no models',
        () {
      writeGlobal('{}');
      final (cfg, _) = load();
      expect(cfg.isEmpty, isTrue);
    });

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
      expect(load, throwsA(isA<VoiceConfigError>()));
    });

    test('rejects malformed global config.json loudly', () {
      writeGlobal('{not json');
      expect(load, throwsA(isA<VoiceConfigError>()));
    });

    test('rejects a non-object top level in config.json', () {
      writeGlobal('[1,2,3]');
      expect(load, throwsA(isA<VoiceConfigError>()));
    });

    test('rejects a non-object providers entry', () {
      writeGlobal('{"providers": {"openrouter": "sk-or"}}');
      expect(load, throwsA(isA<VoiceConfigError>()));
    });

    test('rejects a non-string value inside a providers entry', () {
      writeGlobal('{"providers": {"openrouter": {"KEY": 42}}}');
      expect(load, throwsA(isA<VoiceConfigError>()));
    });

    test('parses the required model-file provider', () {
        writeModel('gemini', '{"id": "a/b", "provider": "google"}');
        writeModel('fish', '{"id": "a/b", "provider": "openrouter"}');
        final (cfg, _) = load();
        expect(cfg.models['gemini']?.provider, 'google');
        expect(cfg.models['fish']?.provider, 'openrouter');
      },
    );

    test('skips a model file with a missing provider and reports a warning', () {
      writeModel('x', '{"id": "a/b"}');
      final (cfg, warnings) = load();
      expect(cfg.models, isEmpty);
      expect(warnings.single, contains('Skipped model "x"'));
      expect(warnings.single, contains('"provider"'));
    });

    test('an unknown default_model warns and keeps the fish fallback', () {
      writeGlobal('{"default_model": "bogus"}');
      writeModel('fish', '{"id": "a/b", "provider": "openrouter"}');
      final (cfg, warnings) = load();
      expect(cfg.defaultModel, 'bogus');
      expect(defaultModelFor(cfg).alias, kDefaultProfile.profile.alias);
      expect(warnings.single, contains('default_model "bogus"'));
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

  group('defaultModelFor', () {
    test('empty config falls back to the compiled fish bootstrap', () {
      expect(defaultModelFor(const VoiceConfig()).alias, 'fish');
    });

    test('resolves default_model by alias', () {
      final cfg = VoiceConfig(
        defaultModel: 'gemini',
        models: {
          'gemini': const TtsModelProfile(
            alias: 'gemini',
            id: 'google/gemini-3.1-flash-tts-preview',
          ),
        },
      );
      expect(defaultModelFor(cfg).alias, 'gemini');
    });

    test('resolves default_model by full id', () {
      final cfg = VoiceConfig(
        defaultModel: 'google/gemini-3.1-flash-tts-preview',
        models: {
          'gemini': const TtsModelProfile(
            alias: 'gemini',
            id: 'google/gemini-3.1-flash-tts-preview',
          ),
        },
      );
      expect(defaultModelFor(cfg).alias, 'gemini');
    });

    test('an unknown default_model falls back to fish', () {
      final cfg = VoiceConfig(defaultModel: 'bogus');
      expect(defaultModelFor(cfg).alias, kDefaultProfile.profile.alias);
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

    (VoiceConfig, List<String>) read() => loadVoiceConfig('${dir.path}/cfg');

    test('round-trips default_model, providers, models, defaults, pricing and aliases', () {
      writeVoiceConfig(
        '${dir.path}/cfg',
        VoiceConfig(
          defaultModel: 'fish',
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
            'kokoro': const TtsModelProfile(
              alias: 'kokoro',
              id: 'hexgrad/kokoro-82m',
              format: 'mp3',
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
      final (cfg, warnings) = read();
      expect(warnings, isEmpty);
      expect(cfg.defaultModel, 'fish');
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

    test('empty config writes an empty config.json and no model files', () {
      writeVoiceConfig('${dir.path}/cfg', const VoiceConfig());
      expect(
        File('${dir.path}/cfg${Platform.pathSeparator}config.json')
            .readAsStringSync(),
        contains('{}'),
      );
      expect(
        Directory('${dir.path}/cfg').listSync().whereType<File>().toList(),
        hasLength(1),
      );
    });

    test('creates missing parent directories', () {
      writeVoiceConfig(
        '${dir.path}/a/b/c',
        const VoiceConfig(defaultModel: 'fish'),
      );
      expect(
        File('${dir.path}/a/b/c${Platform.pathSeparator}config.json')
            .existsSync(),
        isTrue,
      );
    });

    test('round-trips default_model and the providers block verbatim', () {
      writeVoiceConfig(
        '${dir.path}/cfg',
        const VoiceConfig(
          defaultModel: 'fish',
          providers: {
            'openrouter': {'OPENROUTER_API_KEY': r'${OPENROUTER_API_KEY}'},
          },
        ),
      );
      expect(read().$1.defaultModel, 'fish');
      expect(read().$2, isEmpty);
      // The env reference survives in the global file, unresolved.
      expect(
        File('${dir.path}/cfg${Platform.pathSeparator}config.json')
            .readAsStringSync(),
        contains(r'${OPENROUTER_API_KEY}'),
      );
    });

    test('round-trips a per-model provider override', () {
      writeVoiceConfig(
        '${dir.path}/cfg',
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
      expect(read().$1.models['gemini']?.provider, 'google');
    });

    test('always writes the provider into each model file', () {
      writeVoiceConfig(
        '${dir.path}/cfg',
        const VoiceConfig(
          models: {
            'gemini': TtsModelProfile(
              alias: 'gemini',
              id: 'a/b',
              provider: 'openrouter',
            ),
          },
        ),
      );
      final raw = File(
        '${dir.path}/cfg${Platform.pathSeparator}gemini.json',
      ).readAsStringSync();
      expect(raw, contains('"provider": "openrouter"'));
      expect(read().$1.models['gemini']?.provider, 'openrouter');
    });

    test('throws VoiceConfigError when the path cannot be written', () {
      expect(
        () => writeVoiceConfig(
          '/dev/null/cfg',
          const VoiceConfig(defaultModel: 'x'),
        ),
        throwsA(isA<VoiceConfigError>()),
      );
    });
  });

  group('defaultConfigDir', () {
    test('always ends with the config directory name', () {
      expect(defaultConfigDir(), endsWith('tts-narrator'));
    });

    test('uses the Unix config dir on non-Windows hosts', () {
      if (Platform.isWindows) return;
      final p = defaultConfigDir();
      expect(p, contains('.config/tts-narrator'));
    });
  });
}