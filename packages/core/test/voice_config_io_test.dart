import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/voice_config.dart';
import 'package:tts_narrator_core/src/config/voice_config_io.dart';
import 'package:tts_narrator_core/src/config/voice_config_queries.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';

import 'support/fake_provider.dart';

void main() {
  group('loadVoiceConfig', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tts_config_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    String at(String dirName, String file) =>
        '${dir.path}${Platform.pathSeparator}$dirName'
        '${Platform.pathSeparator}$file';

    void writeRegistry(String contents) =>
        File('${dir.path}${Platform.pathSeparator}$kVoiceConfigRegistryName')
            .writeAsStringSync(contents);

    void writeProvider(String name, String contents) {
      final file = File(at(kVoiceConfigProvidersDir, '$name.json'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    void writeModel(String alias, String contents) {
      final file = File(at(kVoiceConfigModelsDir, '$alias.json'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    /// Registers [name] and writes a provider block claiming [models].
    void writeClaimingProvider(
      String name, {
      List<String> models = const [],
      String settings = '{"base_url":"$testBaseUrl"}',
    }) {
      writeRegistry(
        jsonEncode({
          'providers': [name],
        }),
      );
      writeProvider(
        name,
        jsonEncode({'models': models, 'settings': jsonDecode(settings)}),
      );
    }

    (VoiceConfig, List<String>) load() => loadVoiceConfig(dir.path);

    test('missing directory yields an empty config and no warnings', () {
      final (cfg, warnings) = load();
      expect(cfg.isEmpty, isTrue);
      expect(cfg.providers, isEmpty);
      expect(cfg.voices, isEmpty);
      expect(warnings, isEmpty);
    });

    test('parses per-model files into request profiles', () {
      writeClaimingProvider(testProvider, models: ['gemini']);
      writeModel(
        'gemini',
        '{"id":"google/gemini-3.1-flash-tts-preview","format":"pcm",'
            '"sample_rate":24000,"prompt_style":true}',
      );
      final (cfg, warnings) = load();
      expect(cfg.models.containsKey('gemini'), isTrue);
      expect(cfg.models['gemini']!.provider, testProvider);
      expect(warnings, isEmpty);
    });

    group('speed capability', () {
      TtsModelProfile loadProfile(String json) {
        writeClaimingProvider(testProvider, models: ['m']);
        writeModel('m', json);
        return load().$1.models['m']!;
      }

      test('defaults to unsupported when the key is absent', () {
        expect(loadProfile('{"id":"x/y"}').supportsSpeed, isFalse);
      });

      test('reads the opt-in flag', () {
        expect(loadProfile('{"id":"x/y","speed":true}').supportsSpeed, isTrue);
        expect(
          loadProfile('{"id":"x/y","speed":false}').supportsSpeed,
          isFalse,
        );
      });

      test('rejects a non-bool', () {
        writeClaimingProvider(testProvider, models: ['m']);
        writeModel('m', '{"id":"x/y","speed":"yes"}');
        final (_, warnings) = load();
        expect(warnings.first, contains('"speed" must be a bool'));
      });
    });

    group('language table', () {
      const kokoroJson =
          '{"id":"hexgrad/kokoro-82m","sends_language":true,'
          '"default_language":"b","languages":{"b":"British English",'
          '"j":"Japanese"}}';

      VoiceConfig loadConfig(String json) {
        writeClaimingProvider(testProvider, models: ['m']);
        writeModel('m', json);
        final (cfg, warnings) = load();
        expect(warnings, isEmpty);
        return cfg;
      }

      test('reads the table, the default and the opt-in flag', () {
        final cfg = loadConfig(kokoroJson);
        expect(cfg.models['m']!.sendsLanguageField, isTrue);
        expect(cfg.languagesFor('m'), {
          'b': 'British English',
          'j': 'Japanese',
        });
        expect(cfg.defaultLanguageFor('m'), 'b');
      });

      test('a model with no languages reads as none', () {
        final cfg = loadConfig('{"id":"x/y"}');
        expect(cfg.models['m']!.sendsLanguageField, isFalse);
        expect(cfg.languagesFor('m'), isEmpty);
        expect(cfg.defaultLanguageFor('m'), isNull);
      });

      test('rejects a non-bool sends_language', () {
        writeClaimingProvider(testProvider, models: ['m']);
        writeModel('m', '{"id":"x/y","sends_language":"yes"}');
        expect(load().$2.first, contains('"sends_language" must be a bool'));
      });

      test('rejects a default_language the table does not declare', () {
        writeClaimingProvider(testProvider, models: ['m']);
        writeModel(
          'm',
          '{"id":"x/y","languages":{"b":"British"},"default_language":"z"}',
        );
        expect(load().$2.first, contains('"default_language" is "z"'));
      });

      test('rejects a blank language label', () {
        writeClaimingProvider(testProvider, models: ['m']);
        writeModel('m', '{"id":"x/y","languages":{"b":""}}');
        expect(load().$2.first, contains('"languages"'));
      });
    });

    test(
      'accepts a directory with only an empty config.json and no models',
      () {
        writeRegistry('{}');
        final (cfg, warnings) = load();
        expect(cfg.isEmpty, isTrue);
        expect(warnings, isEmpty);
      },
    );

    group('provider files', () {
      test('reads the settings block and the claimed model list', () {
        writeRegistry('{"providers":["alpha","beta"]}');
        writeProvider(
          'alpha',
          '{"models":["one","two"],"settings":{"base_url":"https://a/v1",'
              r'"api_key":"${A_KEY}"}}',
        );
        writeProvider('beta', '{"models":[],"settings":{}}');
        writeModel('one', '{"id":"x/one"}');
        writeModel('two', '{"id":"x/two"}');

        final (cfg, warnings) = load();
        expect(warnings, isEmpty);
        expect(cfg.providers.keys, ['alpha', 'beta']);
        final alpha = cfg.providers['alpha']!;
        expect(alpha.name, 'alpha');
        expect(alpha.models, ['one', 'two']);
        expect(alpha.settings['api_key'], r'${A_KEY}');
        expect(alpha.settings['base_url'], 'https://a/v1');
      });

      test('keeps the registry order, not the filename order', () {
        writeRegistry('{"providers":["zeta","alpha"]}');
        writeProvider('zeta', '{"models":[],"settings":{}}');
        writeProvider('alpha', '{"models":[],"settings":{}}');
        expect(load().$1.providers.keys, ['zeta', 'alpha']);
      });

      test('a provider file missing from the registry is ignored loudly', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider('alpha', '{"models":[],"settings":{}}');
        writeProvider('stray', '{"models":[],"settings":{}}');

        final (cfg, warnings) = load();
        expect(cfg.providers.containsKey('stray'), isFalse);
        expect(warnings.single, contains('stray.json'));
        expect(warnings.single, contains('not listed in config.json'));
      });

      test('rejects a non-object settings entry', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider('alpha', '{"models":[],"settings":{"base_url":1}}');
        final (_, warnings) = load();
        expect(
          warnings.join('\n'),
          contains('"settings.base_url" must be a string'),
        );
      });

      test('rejects a non-list models entry', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider('alpha', '{"models":"one","settings":{}}');
        final (_, warnings) = load();
        expect(warnings.join('\n'), contains('"models" must be a list'));
      });
    });

    group('model to provider inversion', () {
      test('stamps the claiming provider onto each profile', () {
        writeRegistry('{"providers":["alpha","beta"]}');
        writeProvider('alpha', '{"models":["one"],"settings":{}}');
        writeProvider('beta', '{"models":["two"],"settings":{}}');
        writeModel('one', '{"id":"x/one"}');
        writeModel('two', '{"id":"x/two"}');

        final (cfg, warnings) = load();
        expect(warnings, isEmpty);
        expect(cfg.models['one']!.provider, 'alpha');
        expect(cfg.models['two']!.provider, 'beta');
      });

      test('a model no provider claims is skipped without a warning', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider('alpha', '{"models":["one"],"settings":{}}');
        writeModel('one', '{"id":"x/one"}');
        writeModel('orphan', '{"id":"x/orphan"}');

        final (cfg, warnings) = load();
        expect(cfg.models.containsKey('one'), isTrue);
        expect(cfg.models.containsKey('orphan'), isFalse);
        expect(warnings, isEmpty);
      });

      test('warns when a provider lists a model that did not load', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider('alpha', '{"models":["gone"],"settings":{}}');

        final (_, warnings) = load();
        expect(warnings.single, contains('gone'));
      });
    });

    group('defaultModelFor', () {
      test('is the first model of the first provider', () {
        writeRegistry('{"providers":["alpha","beta"]}');
        writeProvider('alpha', '{"models":["one","two"],"settings":{}}');
        writeProvider('beta', '{"models":["three"],"settings":{}}');
        writeModel('one', '{"id":"x/one"}');
        writeModel('two', '{"id":"x/two"}');
        writeModel('three', '{"id":"x/three"}');

        expect(defaultModelFor(load().$1)?.alias, 'one');
      });

      test('is null when no provider is registered', () {
        writeRegistry('{}');
        expect(defaultModelFor(load().$1), isNull);
      });

      test('is null when the first provider lists no models', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider('alpha', '{"models":[],"settings":{}}');
        expect(defaultModelFor(load().$1), isNull);
      });
    });
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

    String at(String dirName, String file) =>
        '${dir.path}${Platform.pathSeparator}$dirName'
        '${Platform.pathSeparator}$file';

    test('writes the provider registry to config.json', () {
      writeVoiceConfig(
        dir.path,
        VoiceConfig(
          providers: {
            'zeta': const ProviderConfig(name: 'zeta'),
            'alpha': const ProviderConfig(name: 'alpha'),
          },
        ),
      );
      final raw = jsonDecode(
        File('${dir.path}${Platform.pathSeparator}config.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(raw['providers'], ['zeta', 'alpha']);
    });

    test('round-trips the speed capability through a model file', () {
      writeVoiceConfig(
        dir.path,
        VoiceConfig(
          providers: {
            testProvider: ProviderConfig(
              name: testProvider,
              settings: {'base_url': testBaseUrl},
              models: const ['fast', 'plain'],
            ),
          },
          models: {
            'fast': const TtsModelProfile(
              alias: 'fast',
              id: 'x/y',
              supportsSpeed: true,
              provider: testProvider,
            ),
            'plain': const TtsModelProfile(
              alias: 'plain',
              id: 'x/z',
              provider: testProvider,
            ),
          },
        ),
      );

      final raw = jsonDecode(
        File(at(kVoiceConfigModelsDir, 'fast.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(raw['speed'], isTrue);
      expect(raw.containsKey('provider'), isFalse);

      final (cfg, warnings) = loadVoiceConfig(dir.path);
      expect(warnings, isEmpty);
      expect(cfg.models['fast']!.supportsSpeed, isTrue);
      expect(cfg.models['plain']!.supportsSpeed, isFalse);
      expect(cfg.models['fast']!.provider, testProvider);
    });

    test('round-trips the language table through a model file', () {
      writeVoiceConfig(
        dir.path,
        VoiceConfig(
          providers: {
            testProvider: ProviderConfig(
              name: testProvider,
              settings: {'base_url': testBaseUrl},
              models: const ['kokoro'],
            ),
          },
          models: {
            'kokoro': const TtsModelProfile(
              alias: 'kokoro',
              id: 'hexgrad/kokoro-82m',
              sendsLanguageField: true,
              provider: testProvider,
            ),
          },
          languages: {
            'kokoro': {'b': 'British English', 'j': 'Japanese'},
          },
          defaultLanguages: {'kokoro': 'b'},
        ),
      );

      final raw = jsonDecode(
        File(at(kVoiceConfigModelsDir, 'kokoro.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(raw['sends_language'], isTrue);
      expect(raw['default_language'], 'b');
      expect(raw['languages'], {'b': 'British English', 'j': 'Japanese'});

      final (cfg, warnings) = loadVoiceConfig(dir.path);
      expect(warnings, isEmpty);
      expect(cfg.models['kokoro']!.sendsLanguageField, isTrue);
      expect(cfg.languagesFor('kokoro'), {
        'b': 'British English',
        'j': 'Japanese',
      });
      expect(cfg.defaultLanguageFor('kokoro'), 'b');
    });

    test('a model with no languages emits no language keys', () {
      writeVoiceConfig(
        dir.path,
        VoiceConfig(
          providers: {
            testProvider: const ProviderConfig(
              name: testProvider,
              models: ['one'],
            ),
          },
          models: {
            'one': const TtsModelProfile(
              alias: 'one',
              id: 'x/one',
              provider: testProvider,
            ),
          },
        ),
      );

      final raw = jsonDecode(
        File(at(kVoiceConfigModelsDir, 'one.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(raw.containsKey('sends_language'), isFalse);
      expect(raw.containsKey('default_language'), isFalse);
      expect(raw.containsKey('languages'), isFalse);
    });

    test('round-trips the whole tree back into an equal config', () {
      final original = VoiceConfig(
        providers: {
          testProvider: ProviderConfig(
            name: testProvider,
            settings: {'base_url': testBaseUrl},
            models: const ['one'],
          ),
        },
        models: {
          'one': const TtsModelProfile(
            alias: 'one',
            id: 'x/one',
            provider: testProvider,
          ),
        },
      );
      writeVoiceConfig(dir.path, original);

      final (reloaded, warnings) = loadVoiceConfig(dir.path);
      expect(warnings, isEmpty);
      expect(reloaded.providers.keys, original.providers.keys);
      expect(
        reloaded.providers[testProvider]!.settings,
        original.providers[testProvider]!.settings,
      );
      expect(reloaded.providers[testProvider]!.models, ['one']);
      expect(reloaded.models['one']!.id, 'x/one');
      expect(reloaded.models['one']!.provider, testProvider);
    });

    test('a model missing from its provider list still round-trips', () {
      writeVoiceConfig(
        dir.path,
        VoiceConfig(
          providers: {
            testProvider: const ProviderConfig(name: testProvider, models: []),
          },
          models: {
            'stray': const TtsModelProfile(
              alias: 'stray',
              id: 'x/stray',
              provider: testProvider,
            ),
          },
        ),
      );

      final (reloaded, warnings) = loadVoiceConfig(dir.path);
      expect(warnings, isEmpty);
      expect(reloaded.providers[testProvider]!.models, ['stray']);
      expect(reloaded.models['stray'], isNotNull);
    });
  });
}
