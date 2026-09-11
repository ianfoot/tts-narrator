import 'package:test/test.dart';
import 'package:tts_narrator_core/src/cli/voice_config.dart';
import 'package:tts_narrator_core/src/cli/voice_config_queries.dart';
import 'package:tts_narrator_core/src/narration/cost.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';

TtsModelProfile _model({
  required String alias,
  required String id,
  String provider = 'openrouter',
  String format = 'mp3',
  bool promptStyle = false,
  bool sendsVoiceField = true,
  int? sampleRate,
  String? displayName,
}) =>
    TtsModelProfile(
      alias: alias,
      id: id,
      provider: provider,
      format: format,
      promptStyle: promptStyle,
      sendsVoiceField: sendsVoiceField,
      sampleRate: sampleRate,
      displayName: displayName,
    );

VoiceConfig _cfg({
  String? defaultModel,
  Map<String, Map<String, String>> providers = const {},
  Map<String, TtsModelProfile> models = const {},
  Map<String, String> defaults = const {},
  Map<String, AudioPricing> pricing = const {},
  Map<String, Map<String, Voice>> voices = const {},
}) =>
    VoiceConfig(
      defaultModel: defaultModel,
      providers: providers,
      models: models,
      defaults: defaults,
      pricing: pricing,
      voices: voices,
    );

void main() {
  group('effectiveModels', () {
    test('with an empty config, only the fish bootstrap exists', () {
      final models = effectiveModels(const VoiceConfig());
      expect(models.length, 1);
      expect(models.firstWhere((m) => m.alias == 'fish'), isNotNull);
    });

    test('config models extend the set with new providers', () {
      final cfg = _cfg(
        models: {
          'kokoro': _model(alias: 'kokoro', id: 'hexgrad/kokoro-82m'),
        },
        defaults: const {'kokoro': 'Emma'},
      );
      final models = effectiveModels(cfg);
      expect(models.length, 2);
      expect(models.any((m) => m.alias == 'fish'), isTrue);
      expect(models.any((m) => m.alias == 'kokoro'), isTrue);
    });

    test('a config model overrides the fish bootstrap by alias', () {
      final cfg = _cfg(
        models: {'fish': _model(alias: 'fish', id: 'custom/fish-model')},
      );
      final models = effectiveModels(cfg);
      expect(models.length, 1);
      expect(models.firstWhere((m) => m.alias == 'fish').id, 'custom/fish-model');
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
      expect(profile!.provider, 'openrouter');
    });

    test('fish bootstraps in with an empty config', () {
      final profile = profileFor('fish', const VoiceConfig());
      expect(profile, isNotNull);
      expect(profile!.provider, 'openrouter');
    });

    test('returns null for unknown names', () {
      expect(profileFor('unknown', const VoiceConfig()), isNull);
    });
  });

  group('defaultModelFor', () {
    test('empty config falls back to the compiled fish bootstrap', () {
      expect(defaultModelFor(const VoiceConfig()).alias, 'fish');
    });

    test('resolves default_model by alias', () {
      final cfg = _cfg(
        defaultModel: 'gemini',
        models: {'gemini': _model(alias: 'gemini', id: 'google/gemini-tts')},
      );
      expect(defaultModelFor(cfg).alias, 'gemini');
    });

    test('resolves default_model by full id', () {
      final cfg = _cfg(
        defaultModel: 'google/gemini-tts',
        models: {'gemini': _model(alias: 'gemini', id: 'google/gemini-tts')},
      );
      expect(defaultModelFor(cfg).alias, 'gemini');
    });

    test('an unknown default_model falls back to fish', () {
      final cfg = _cfg(defaultModel: 'unknown');
      expect(defaultModelFor(cfg).alias, 'fish');
    });
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
    test('uses the configured default label', () {
      final cfg = _cfg(
        voices: const {'kokoro': {'Emma': Voice(id: 'bf_emma')}},
        defaults: const {'kokoro': 'Emma'},
        models: {'kokoro': _model(alias: 'kokoro', id: 'hexgrad/kokoro-82m')},
      );
      final model = profileFor('kokoro', cfg)!;
      final (id, label) = defaultVoiceFor(model, cfg);
      expect(label, 'Emma');
    });

    test('fish falls back to the compiled bootstrap voice', () {
      final cfg = _cfg(
        voices: const {'fish': {'British Female Narrator': Voice(id: '89f41ea230034706881f85a8227d6ab9')}},
        models: {'fish': _model(alias: 'fish', id: 'fish-audio/s2.1-pro-free')},
      );
      final model = profileFor('fish', cfg)!;
      final (id, label) = defaultVoiceFor(model, cfg);
      expect(label, 'British Female Narrator');
    });

    test('throws when a model has no default configured', () {
      final cfg = _cfg(
        voices: const {'gemini': {'Voice1': Voice(id: 'v1')}},
        models: {'gemini': _model(alias: 'gemini', id: 'google/gemini-tts')},
      );
      final model = profileFor('gemini', cfg)!;
      expect(() => defaultVoiceFor(model, cfg), throwsA(isA<VoiceConfigurationError>()));
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
      final entries = voiceEntries(config: cfg, model: profileFor('kokoro', cfg)!);
      // When the default voice is in the voices map, it stays as alias (deduped)
      expect(entries.length, 3);
      final labels = entries.map((e) => e.label).toSet();
      expect(labels, {'Emma', 'Daniel', 'Sarah'});
      expect(entries.where((e) => e.isAlias).length, 3);
    });

    test('covers all effective models when none is given', () {
      final cfg = _cfg(
        voices: const {
          'fish': {'British Female Narrator': Voice(id: '89f41ea230034706881f85a8227d6ab9')},
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
      final entries = voiceEntries(config: cfg, model: profileFor('kokoro', cfg)!);
      final emma = entries.firstWhere((e) => e.label == 'Emma');
      final daniel = entries.firstWhere((e) => e.label == 'Daniel');
      expect(emma.gender, VoiceGender.female);
      expect(daniel.gender, VoiceGender.male);
    });
  });
}