import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/voice_config.dart';
import 'package:tts_narrator_core/src/config/voice_config_queries.dart';
import 'package:tts_narrator_core/src/narration/audio_format.dart';
import 'package:tts_narrator_core/src/narration/cost.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';

import 'support/fake_provider.dart';

TtsModelProfile _model({
  required String alias,
  required String id,
  String provider = testProvider,
  bool promptStyle = false,
  bool sendsVoiceField = true,
  String? displayName,
}) => TtsModelProfile(
  alias: alias,
  id: id,
  formats: const [TtsAudioFormat.wav],
  provider: provider,
  promptStyle: promptStyle,
  sendsVoiceField: sendsVoiceField,
  displayName: displayName,
);

VoiceConfig _cfg({
  Map<String, ProviderConfig> providers = const {},
  Map<String, TtsModelProfile> models = const {},
  Map<String, String> defaults = const {},
  Map<String, AudioPricing> pricing = const {},
  Map<String, Map<String, String>> languages = const {},
  Map<String, String> defaultLanguages = const {},
  Map<String, Map<String, Voice>> voices = const {},
}) => VoiceConfig(
  providers: providers,
  models: models,
  defaults: defaults,
  pricing: pricing,
  voices: voices,
  languages: languages,
  defaultLanguages: defaultLanguages,
);

/// A Kokoro-shaped config: two languages, voices whose ids name them.
VoiceConfig _kokoroCfg({Map<String, Map<String, Voice>>? voices}) => _cfg(
  voices:
      voices ??
      const {
        'kokoro': {
          'bf_emma': Voice(id: 'bf_emma', gender: VoiceGender.female),
          'jm_kumo': Voice(id: 'jm_kumo', gender: VoiceGender.male),
        },
      },
  models: {'kokoro': _model(alias: 'kokoro', id: 'hexgrad/kokoro-82m')},
  languages: const {
    'kokoro': {
      'a': 'American English',
      'b': 'British English',
      'j': 'Japanese',
    },
  },
  defaultLanguages: const {'kokoro': 'b'},
);

TtsModelProfile _kokoroModel(VoiceConfig cfg) => profileFor('kokoro', cfg)!;

void main() {
  group('effectiveModels', () {
    test('an empty config yields no models (no compiled default)', () {
      final models = effectiveModels(const VoiceConfig());
      expect(models, isEmpty);
    });

    test('returns the configured models, sorted by alias', () {
      final cfg = _cfg(
        models: {
          'kokoro': _model(alias: 'kokoro', id: 'hexgrad/kokoro-82m'),
          'fish': _model(alias: 'fish', id: 'fish-audio/s2.1-pro-free'),
        },
        defaults: const {'kokoro': 'Emma'},
      );
      final models = effectiveModels(cfg);
      expect(models.map((m) => m.alias), ['fish', 'kokoro']);
    });
  });

  group('profileFor', () {
    test('resolves a config alias or full id', () {
      final cfg = _cfg(
        models: {'gemini': _model(alias: 'gemini', id: 'google/gemini-tts')},
        defaults: const {'gemini': 'Emma'},
      );
      final profile = profileFor('gemini', cfg);
      expect(profile, isNotNull);
      expect(profile!.provider, testProvider);
    });

    for (final name in const ['fish', 'unknown', 'google/gemini-tts']) {
      test('returns null for the unknown name $name', () {
        expect(profileFor(name, const VoiceConfig()), isNull);
      });
    }
  });

  group('defaultModelFor', () {
    ProviderConfig provider(String name, List<String> models) =>
        ProviderConfig(name: name, models: models);

    test('empty config has no default model (no compiled default)', () {
      expect(defaultModelFor(const VoiceConfig()), isNull);
    });

    test('is the first model of the first registered provider', () {
      final cfg = _cfg(
        providers: {
          'alpha': provider('alpha', ['gemini', 'kokoro']),
          'beta': provider('beta', ['fish']),
        },
        models: {
          'gemini': _model(alias: 'gemini', id: 'google/gemini-tts'),
          'kokoro': _model(alias: 'kokoro', id: 'hexgrad/kokoro-82m'),
          'fish': _model(alias: 'fish', id: 'fish-audio/s2.1-pro-free'),
        },
      );
      expect(defaultModelFor(cfg)!.alias, 'gemini');
    });

    test('provider order decides, not model alias order', () {
      final cfg = _cfg(
        providers: {
          'beta': provider('beta', ['fish']),
        },
        models: {
          'gemini': _model(alias: 'gemini', id: 'google/gemini-tts'),
          'fish': _model(alias: 'fish', id: 'fish-audio/s2.1-pro-free'),
        },
      );
      expect(defaultModelFor(cfg)!.alias, 'fish');
    });

    test('resolves a provider entry naming a full id', () {
      final cfg = _cfg(
        providers: {
          'alpha': provider('alpha', ['google/gemini-tts']),
        },
        models: {'gemini': _model(alias: 'gemini', id: 'google/gemini-tts')},
      );
      expect(defaultModelFor(cfg)!.alias, 'gemini');
    });

    // A default can only come from a registered provider whose entry names a model
    // the config actually carries.
    for (final (name, providers) in <(String, Map<String, ProviderConfig>)>[
      (
        'a provider entry naming an unknown model',
        {'alpha': ProviderConfig(name: 'alpha', models: ['unknown'])},
      ),
      (
        'a provider claiming no models',
        {'alpha': ProviderConfig(name: 'alpha', models: [])},
      ),
      ('models with no provider block', const {}),
    ]) {
      test('$name yields no default', () {
        final cfg = _cfg(
          providers: providers,
          models: {'gemini': _model(alias: 'gemini', id: 'google/gemini-tts')},
        );
        expect(defaultModelFor(cfg), isNull);
      });
    }
  });

  group('resolveVoice', () {
    final cfg = _cfg(
      voices: {
        'fish': const {'British Female Narrator (good)': Voice(id: '89f41ea')},
        'kokoro': const {'Emma': Voice(id: 'bf_emma')},
      },
    );

    test('resolves an alias to its raw id and keeps the label', () {
      final (id, label) = resolveVoice(
        cfg,
        'fish',
        'British Female Narrator (good)',
      );
      expect(id, '89f41ea');
      expect(label, 'British Female Narrator (good)');
    });

    test('passes unknown values through unchanged', () {
      final (id, label) = resolveVoice(
        cfg,
        'fish',
        '2fd511bd06904a21a971c6551dfb853a',
      );
      expect(id, '2fd511bd06904a21a971c6551dfb853a');
      expect(label, '2fd511bd06904a21a971c6551dfb853a');
    });

    test('is isolated per model', () {
      final (id, _) = resolveVoice(
        cfg,
        'kokoro',
        'British Female Narrator (good)',
      );
      expect(id, 'British Female Narrator (good)');
      final (id2, _) = resolveVoice(cfg, 'gemini', 'Emma');
      expect(id2, 'Emma');
    });

    test('empty config passes everything through', () {
      final (id, label) = resolveVoice(const VoiceConfig(), 'fish', 'anything');
      expect(id, 'anything');
      expect(label, 'anything');
    });
  });

  group('parseVoiceGender', () {
    test('parses the config spellings case-insensitively', () {
      expect(parseVoiceGender('male'), VoiceGender.male);
      expect(parseVoiceGender('MALE'), VoiceGender.male);
      expect(parseVoiceGender('female'), VoiceGender.female);
      expect(parseVoiceGender('Female'), VoiceGender.female);
      expect(parseVoiceGender('neutral'), VoiceGender.neutral);
      expect(parseVoiceGender('NEUTRAL'), VoiceGender.neutral);
    });

    test('returns null for null, empty and unknown input', () {
      expect(parseVoiceGender(null), isNull);
      expect(parseVoiceGender(''), isNull);
      expect(parseVoiceGender('unknown'), isNull);
    });
  });

  group('genderFor', () {
    final cfg = _cfg(
      voices: const {
        'kokoro': {'Emma': Voice(id: 'bf_emma', gender: VoiceGender.female)},
      },
    );

    test('looks up a tag by voice label under the model alias', () {
      expect(genderFor(cfg, 'kokoro', 'Emma'), VoiceGender.female);
      expect(genderFor(cfg, 'kokoro', 'Daniel'), isNull);
      expect(genderFor(cfg, 'gemini', 'Emma'), isNull);
    });
  });

  group('genderFromVoiceId', () {
    test('reads the second character of a <lang><gender>_<name> id', () {
      expect(genderFromVoiceId('bf_emma'), VoiceGender.female);
      expect(genderFromVoiceId('jm_kumo'), VoiceGender.male);
      expect(genderFromVoiceId('xn_something'), VoiceGender.neutral);
    });

    test('is null for an id that names no gender', () {
      expect(genderFromVoiceId('b'), isNull);
      expect(genderFromVoiceId(''), isNull);
      expect(genderFromVoiceId('bzy_thing'), isNull);
    });
  });

  group('genderFor from the voice id', () {
    final cfg = _kokoroCfg(
      voices: const {
        'kokoro': {'Emma': Voice(id: 'bf_emma'), 'Kumo': Voice(id: 'jm_kumo')},
      },
    );

    test('reads the gender off an untagged voice id', () {
      expect(genderFor(cfg, 'kokoro', 'Emma'), VoiceGender.female);
      expect(genderFor(cfg, 'kokoro', 'Kumo'), VoiceGender.male);
    });

    test('reads it off a raw id that is not a configured entry', () {
      expect(genderFor(cfg, 'kokoro', 'zf_xiaoxiao'), VoiceGender.female);
    });

    test('leaves a model that declares no languages untagged', () {
      final plain = _cfg(
        voices: const {
          'gemini': {'Nala': Voice(id: 'nala')},
        },
      );
      expect(genderFor(plain, 'gemini', 'Nala'), isNull);
      expect(genderFor(plain, 'gemini', 'nala'), isNull);
    });
  });

  group('pricingFor', () {
    final cfg = _cfg(
      pricing: const {
        'fish': AudioPricing(outputUsdPerMTokens: 1.5),
        'kokoro': AudioPricing(usdPerMChars: 0.5),
      },
    );

    test('returns the configured pricing for a model', () {
      final pricing = pricingFor(cfg, 'fish');
      expect(pricing, isNotNull);
      expect(pricing.outputUsdPerMTokens, 1.5);
    });

    test('returns freePricing for unknown model', () {
      expect(pricingFor(cfg, 'unknown'), freePricing);
    });
  });

  group('defaultVoiceFor', () {
    

    test('uses the configured default voice for a model', () {
      final cfg = _cfg(
        voices: const {
          'fish': {
            'British Female Narrator': Voice(
              id: '89f41ea230034706881f85a8227d6ab9',
            ),
          },
        },
        defaults: const {'fish': 'British Female Narrator'},
        models: {'fish': _model(alias: 'fish', id: 'fish-audio/s2.1-pro-free')},
      );
      final model = profileFor('fish', cfg)!;
      final (id, label) = defaultVoiceFor(model, cfg);
      expect(id, '89f41ea230034706881f85a8227d6ab9');
      expect(label, 'British Female Narrator');
    });

    test('throws when a model has no default configured', () {
      final cfg = _cfg(
        voices: const {
          'gemini': {'Voice1': Voice(id: 'v1')},
        },
        models: {'gemini': _model(alias: 'gemini', id: 'google/gemini-tts')},
      );
      final model = profileFor('gemini', cfg)!;
      expect(
        () => defaultVoiceFor(model, cfg),
        throwsA(isA<VoiceConfigurationError>()),
      );
    });
  });

  group('voiceEntries', () {
    test(
      'a configured default voice yields that entry, not a compiled one',
      () {
        final cfg = _cfg(
          defaults: const {'fish': 'British Female Narrator'},
          voices: const {
            'fish': {
              'British Female Narrator': Voice(
                id: '89f41ea230034706881f85a8227d6ab9',
              ),
            },
          },
          models: {
            'fish': _model(alias: 'fish', id: 'fish-audio/s2.1-pro-free'),
          },
        );
        final entries = voiceEntries(
          model: profileFor('fish', cfg)!,
          config: cfg,
        );
        expect(entries, hasLength(1));
        expect(entries.single.id, '89f41ea230034706881f85a8227d6ab9');
        expect(entries.single.label, 'British Female Narrator');
        expect(entries.single.isAlias, isTrue);
      },
    );

    test('a model without aliases or a config default yields no entries', () {
      final entries = voiceEntries(
        model: _model(alias: 'gemini', id: 'google/gemini-tts'),
        config: const VoiceConfig(),
      );
      expect(entries, isEmpty);
    });

    test('includes aliases plus the default voice, deduped', () {
      final cfg = _cfg(
        voices: const {
          'kokoro': {
            'Emma': Voice(id: 'bf_emma'),
            'Daniel': Voice(id: 'bm_daniel'),
            'Sarah': Voice(id: 'bf_sarah'),
          },
        },
        defaults: const {'kokoro': 'Emma'},
        models: {'kokoro': _model(alias: 'kokoro', id: 'hexgrad/kokoro-82m')},
      );
      final entries = voiceEntries(
        config: cfg,
        model: profileFor('kokoro', cfg)!,
      );
      // When the default voice is in the voices map, it stays as alias (deduped)
      expect(entries.length, 3);
      final labels = entries.map((e) => e.label).toSet();
      expect(labels, {'Emma', 'Daniel', 'Sarah'});
      expect(entries.where((e) => e.isAlias).length, 3);
    });

    test('covers all effective models when none is given', () {
      final cfg = _cfg(
        voices: const {
          'fish': {
            'British Female Narrator': Voice(
              id: '89f41ea230034706881f85a8227d6ab9',
            ),
          },
          'kokoro': {'Emma': Voice(id: 'bf_emma')},
        },
        models: {
          'fish': _model(alias: 'fish', id: 'fish-audio/s2.1-pro-free'),
          'kokoro': _model(alias: 'kokoro', id: 'hexgrad/kokoro-82m'),
        },
      );
      final entries = voiceEntries(config: cfg);
      expect(entries.map((e) => e.model).toSet(), {'fish', 'kokoro'});
    });

    test('tags entries with their configured gender', () {
      final cfg = _cfg(
        voices: const {
          'kokoro': {
            'Emma': Voice(id: 'bf_emma', gender: VoiceGender.female),
            'Daniel': Voice(id: 'bm_daniel', gender: VoiceGender.male),
          },
        },
        models: {'kokoro': _model(alias: 'kokoro', id: 'hexgrad/kokoro-82m')},
      );
      final entries = voiceEntries(
        config: cfg,
        model: profileFor('kokoro', cfg)!,
      );
      final emma = entries.firstWhere((e) => e.label == 'Emma');
      final daniel = entries.firstWhere((e) => e.label == 'Daniel');
      expect(emma.gender, VoiceGender.female);
      expect(daniel.gender, VoiceGender.male);
    });

    test(
      'tags entries with the gender their id names when none is declared',
      () {
        final cfg = _kokoroCfg(
          voices: const {
            'kokoro': {
              'Emma': Voice(id: 'bf_emma'),
              'Daniel': Voice(id: 'bm_daniel'),
            },
          },
        );
        final entries = voiceEntries(config: cfg, model: _kokoroModel(cfg));
        expect(
          entries.firstWhere((e) => e.label == 'Emma').gender,
          VoiceGender.female,
        );
        expect(
          entries.firstWhere((e) => e.label == 'Daniel').gender,
          VoiceGender.male,
        );
      },
    );

    test('tags entries with the language their id names', () {
      final cfg = _kokoroCfg();
      final entries = voiceEntries(config: cfg, model: _kokoroModel(cfg));
      expect(entries.firstWhere((e) => e.id == 'bf_emma').language, 'b');
      expect(entries.firstWhere((e) => e.id == 'jm_kumo').language, 'j');
    });

    test('tags entries with their explicit language tag', () {
      // Fish-style: ids are UUIDs, so the tag is the only way to know the
      // language, and it must be read off the voice rather than the id.
      final cfg = _cfg(
        voices: const {
          'fish': {
            'Anne': Voice(id: '7da08ad79a8a4492b2c6b54091499922',
                gender: VoiceGender.female, language: 'en-gb'),
            'Sarah': Voice(id: '933563129e564b19a115bedd57b7406a',
                gender: VoiceGender.female, language: 'en-us'),
          },
        },
        models: {
          'fish': _model(alias: 'fish', id: 'fish-audio/s2.1-pro-free'),
        },
        languages: const {
          'fish': {'en-us': 'US English', 'en-gb': 'British English'},
        },
      );
      final entries = voiceEntries(
        config: cfg,
        model: profileFor('fish', cfg)!,
      );
      expect(entries.firstWhere((e) => e.id == '7da08ad79a8a4492b2c6b54091499922').language, 'en-gb');
      expect(entries.firstWhere((e) => e.id == '933563129e564b19a115bedd57b7406a').language, 'en-us');
    });

    test('a language filter keeps only that language\'s voices', () {
      final cfg = _kokoroCfg();
      final entries = voiceEntries(
        config: cfg,
        model: _kokoroModel(cfg),
        language: 'j',
      );
      expect(entries.map((e) => e.id).toSet(), {'jm_kumo'});
    });

    test('a language filter keeps untagged voices (free-form passthrough)', () {
      final cfg = _cfg(
        voices: const {
          'kokoro': {'Custom': Voice(id: 'brand_new_voice')},
        },
        languages: const {
          'kokoro': {'b': 'British English'},
        },
        models: {'kokoro': _model(alias: 'kokoro', id: 'hexgrad/kokoro-82m')},
      );
      final entries = voiceEntries(
        config: cfg,
        model: profileFor('kokoro', cfg)!,
        language: 'b',
      );
      expect(entries.map((e) => e.id).toSet(), {'brand_new_voice'});
    });
  });

  group('languageFor', () {
    final cfg = _kokoroCfg();

    test('reads the language off the voice id', () {
      expect(languageFor(cfg, 'kokoro', 'bf_emma'), 'b');
      expect(languageFor(cfg, 'kokoro', 'af_bella'), 'a');
    });

    test('null when the id carries no declared language', () {
      expect(languageFor(cfg, 'kokoro', 'custom_voice'), isNull);
      expect(languageFor(cfg, 'kokoro', ''), isNull);
      expect(languageFor(cfg, 'kokoro', 'b'), isNull);
    });

    test('null for a model that declares no languages', () {
      expect(languageFor(cfg, 'fish', 'bf_emma'), isNull);
    });
  });

  group('languageFor with an explicit voice tag', () {
    // Fish-style config: voices keyed by name, ids are UUIDs, so the code
    // cannot be read off the id and must be tagged per voice.
    final cfg = _cfg(
      voices: const {
        'fish': {
          'Anne': Voice(id: '7da08ad79a8a4492b2c6b54091499922',
              gender: VoiceGender.female, language: 'en-gb'),
          'Sarah': Voice(id: '933563129e564b19a115bedd57b7406a',
              gender: VoiceGender.female, language: 'en-us'),
          'Untagged': Voice(id: '00000000000000000000000000000000',
              gender: VoiceGender.neutral),
        },
      },
      models: {
        'fish': _model(alias: 'fish', id: 'fish-audio/s2.1-pro-free'),
      },
      languages: const {
        'fish': {'en-us': 'US English', 'en-gb': 'British English'},
      },
      defaultLanguages: const {'fish': 'en-gb'},
    );

    test('reads the tag off the voice, not the id', () {
      expect(languageFor(cfg, 'fish', 'Anne'), 'en-gb');
      expect(languageFor(cfg, 'fish', 'Sarah'), 'en-us');
    });

    test('reads the tag when the id is looked up by name', () {
      expect(
        languageFor(cfg, 'fish', '7da08ad79a8a4492b2c6b54091499922'),
        'en-gb',
      );
      expect(
        languageFor(cfg, 'fish', '933563129e564b19a115bedd57b7406a'),
        'en-us',
      );
    });

    test('falls back to the id-prefix path when the voice has no tag', () {
      expect(languageFor(cfg, 'fish', 'Untagged'), isNull);
    });

    test('rejects a tag that is not a declared code', () {
      final bad = _cfg(
        voices: const {
          'fish': {
            'Bad': Voice(id: 'abc', language: 'xx'),
          },
        },
        models: {
          'fish': _model(alias: 'fish', id: 'fish-audio/s2.1-pro-free'),
        },
        languages: const {
          'fish': {'en-us': 'US English', 'en-gb': 'British English'},
        },
      );
      expect(languageFor(bad, 'fish', 'Bad'), isNull);
    });
  });
}
