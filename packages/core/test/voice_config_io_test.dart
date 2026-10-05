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

  group('the user overlay', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tts_config_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    String at(String dirName, String file) =>
        '${dir.path}${Platform.pathSeparator}$dirName'
        '${Platform.pathSeparator}$file';

    void writeRegistry(String contents) =>
        File('${dir.path}${Platform.pathSeparator}$kVoiceConfigRegistryName')
            .writeAsStringSync(contents);

    /// The overlay's own registry: a second `config.json`, which the loader
    /// merges with the base rather than the overlay replacing it.
    void writeOverlayRegistry(String contents) {
      final file = File(
        at(kVoiceConfigOverlayDirName, kVoiceConfigRegistryName),
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    /// A file inside [layer]'s providers or models directory. [layer] is either
    /// the config root or the overlay root, so the two call sites below read as
    /// `writeModel(base, ...)` / `writeModel(overlay, ...)` rather than as
    /// duplicated path arithmetic.
    void writeProvider(String layer, String name, String contents) {
      final file = File(at('$layer/$kVoiceConfigProvidersDir', '$name.json'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    void writeModel(String layer, String alias, String contents) {
      final file = File(at('$layer/$kVoiceConfigModelsDir', '$alias.json'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    /// The config root, where the downloaded starter files live.
    const base = '.';
    /// The overlay root, where everything the user authors lands.
    const overlay = kVoiceConfigOverlayDirName;

    String modelJson(String id, {String? defaultVoice}) => jsonEncode({
      'id': id,
      'default_voice': ?defaultVoice,
    });

    /// A base layer claiming [models] for [provider], plus a model file per
    /// alias of the form `<alias>-base`.
    void writeBase({
      String provider = testProvider,
      List<String> models = const ['one'],
      List<String> providerOrder = const [],
      Map<String, String> settingsByProvider = const {},
    }) {
      writeRegistry(
        jsonEncode({
          'providers': providerOrder.isEmpty
              ? [provider]
              : [provider, ...providerOrder],
        }),
      );
      writeProvider(
        base,
        provider,
        jsonEncode({
          'models': models,
          'settings': jsonDecode(
            settingsByProvider[provider] ??
                '{"base_url":"$testBaseUrl"}',
          ),
        }),
      );
      for (final alias in models) {
        writeModel(base, alias, modelJson('$alias-base'));
      }
    }

    (VoiceConfig, List<String>) load() => loadVoiceConfig(dir.path);

    test('the overlay dir name is the documented "user"', () {
      expect(kVoiceConfigOverlayDirName, 'user');
    });

    test('a base-only directory loads exactly as it did before', () {
      writeBase();
      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      expect(cfg.models.keys, ['one']);
      expect(cfg.models['one']!.id, 'one-base');
    });

    test('a model file in the overlay replaces the downloaded one', () {
      writeBase();
      writeModel(overlay, 'one', modelJson('one-overlay'));

      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      expect(cfg.models['one']!.id, 'one-overlay');
    });

    test(
      'an overlay model the base provider still claims needs no overlay '
      'registry',
      () {
        writeBase();
        // The user only ever authored a model file, nothing else.
        writeModel(overlay, 'one', modelJson('one-overlay'));
        final (cfg, _) = load();
        expect(cfg.models['one']!.id, 'one-overlay');
      },
    );

    test('an overlay model only loads once some provider claims it', () {
      writeBase();
      writeModel(overlay, 'two', modelJson('two-overlay'));

      final (cfg, _) = load();
      expect(cfg.models.containsKey('two'), isFalse);
    });

    test('an overlay provider file can claim a model of its own', () {
      writeBase();
      // A provider file the user wrote names a model the downloaded layer never
      // mentions. The overlay registry names it, so the alias can load.
      writeProvider(
        overlay,
        'alpha',
        jsonEncode({
          'models': ['two'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );
      writeModel(overlay, 'two', modelJson('two-overlay'));
      writeOverlayRegistry(jsonEncode({'providers': ['alpha']}));

      final (cfg, _) = load();
      expect(cfg.models['two']!.id, 'two-overlay');
      expect(cfg.models['two']!.provider, 'alpha');
    });

    test('an overlay provider file replaces the downloaded one', () {
      writeBase();
      writeProvider(
        overlay,
        testProvider,
        jsonEncode({
          'models': ['one'],
          'settings': {'base_url': 'https://overlay.example/v1'},
        }),
      );

      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      expect(
        cfg.providers[testProvider]!.settings['base_url'],
        'https://overlay.example/v1',
      );
    });

    test('an inherited provider file override does not reorder the list', () {
      // The documented way to change one setting is to drop a same-named file
      // into the overlay with no registry entry beside it. That is an edit to a
      // provider already in use, so it must not move that provider to the front:
      // being first decides the default model, and editing a base_url should
      // never change which model the app launches on.
      writeBase(provider: 'alpha', providerOrder: const [testProvider]);
      writeProvider(
        base,
        testProvider,
        jsonEncode({
          'models': ['two'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );
      writeModel(base, 'two', modelJson('two-base'));
      writeProvider(
        overlay,
        testProvider,
        jsonEncode({
          'models': ['two'],
          'settings': jsonDecode('{"base_url":"https://overlay.example/v1"}'),
        }),
      );

      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      expect(cfg.providers.keys, ['alpha', testProvider]);
      // The override itself still lands; only its position is left alone.
      expect(
        cfg.providers[testProvider]!.settings['base_url'],
        'https://overlay.example/v1',
      );
      expect(defaultModelFor(cfg)?.alias, 'one');
    });

    test('a provider the overlay registry names does move to the front', () {
      writeBase(provider: 'alpha', providerOrder: const [testProvider]);
      writeProvider(
        base,
        testProvider,
        jsonEncode({
          'models': ['two'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );
      writeModel(base, 'two', modelJson('two-base'));
      writeProvider(
        overlay,
        testProvider,
        jsonEncode({
          'models': ['two'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );
      // Re-listing a provider the baseline already serves is what the README
      // tells a user to do, so it has to be the way to promote one.
      writeOverlayRegistry(jsonEncode({'providers': [testProvider]}));

      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      expect(cfg.providers.keys, [testProvider, 'alpha']);
      expect(defaultModelFor(cfg)?.alias, 'two');
    });

    test('re-listing a downloaded provider warns about nothing', () {
      writeBase(provider: 'alpha', providerOrder: const [testProvider]);
      writeProvider(
        base,
        testProvider,
        jsonEncode({
          'models': ['two'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );
      writeModel(base, 'two', modelJson('two-base'));
      // The registry copied wholesale, with one new name appended -- no overlay
      // file for the re-listed provider, because the downloaded one serves it.
      writeOverlayRegistry(
        jsonEncode({
          'providers': ['alpha', testProvider, 'brand_new'],
        }),
      );
      writeProvider(
        overlay,
        'brand_new',
        jsonEncode({
          'models': ['three'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );
      writeModel(overlay, 'three', modelJson('three-overlay'));

      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      // Only the genuinely new name is promoted; the two re-listed ones keep the
      // baseline's order, which is the point of separating the two lists.
      expect(cfg.providers.keys, ['brand_new', 'alpha', testProvider]);
      expect(cfg.models.keys, containsAll(['one', 'two', 'three']));
    });

    test('an overlay provider registers ahead of the downloaded ones', () {
      writeBase(provider: 'beta', providerOrder: const ['beta']);
      writeRegistry(jsonEncode({'providers': ['beta']}));
      writeProvider(
        overlay,
        'alpha',
        jsonEncode({
          'models': ['two'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );
      writeModel(overlay, 'two', modelJson('two-overlay'));
      writeOverlayRegistry(jsonEncode({'providers': ['alpha']}));

      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      expect(cfg.providers.keys, ['alpha', 'beta']);
    });

    test('an overlay provider file overriding a registered one is not flagged '
        'as unregistered', () {
      writeBase();
      writeProvider(
        overlay,
        testProvider,
        jsonEncode({
          'models': ['one'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );

      final (_, warnings) = load();
      expect(
        warnings.where((w) => w.contains('not listed in config.json')),
        isEmpty,
      );
    });

    test('an overlay provider file the registry never names is ignored with a '
        'warning', () {
      writeBase();
      writeProvider(
        overlay,
        'alpha',
        jsonEncode({
          'models': ['two'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );
      writeModel(overlay, 'two', modelJson('two-overlay'));

      final (cfg, warnings) = load();
      expect(cfg.providers.containsKey('alpha'), isFalse);
      expect(cfg.models.containsKey('two'), isFalse);
      expect(
        warnings.single,
        startsWith('Overlay: Provider file "alpha.json" is not listed'),
      );
    });

    test('overlay warnings are prefixed so their provenance is visible', () {
      writeBase();
      writeModel(overlay, 'one', jsonEncode({'no_id': true}));

      final (_, warnings) = load();
      // The overlay file wins, so the base file's absence of the same key is
      // not reported a second time.
      expect(
        warnings.where((w) => w.startsWith('Overlay: ')),
        hasLength(1),
      );
      expect(warnings, hasLength(1));
    });

    test('voices_editable is read from the file', () {
      writeBase();
      writeModel(
        base,
        'one',
        jsonEncode({'id': 'one-base', 'voices_editable': true}),
      );

      final (cfg, _) = load();
      expect(cfg.models['one']!.voicesEditable, isTrue);
    });

    test('a model that declares no voices_editable reads as locked', () {
      writeBase();
      final (cfg, _) = load();
      expect(cfg.models['one']!.voicesEditable, isFalse);
    });

    test('a non-bool voices_editable is rejected like every other flag', () {
      writeBase();
      writeModel(
        base,
        'one',
        jsonEncode({'id': 'one-base', 'voices_editable': 'yes'}),
      );

      final (cfg, warnings) = load();
      // A wrong type makes the whole model file unusable, exactly as it does
      // for `speed` and `sends_language` — the flag is not silently coerced.
      expect(cfg.models, isEmpty);
      expect(
        warnings.where((w) => w.contains('voices_editable')),
        hasLength(1),
      );
    });

    test('a claim survives an overlay provider dropping it from its list', () {
      writeBase();
      // Claims merge additively, so an overlay provider that stops listing a
      // model does not un-claim it: the base file still claims it and the
      // downloaded model file is still readable. Only a same-named provider file
      // can change who serves an alias.
      writeProvider(
        overlay,
        testProvider,
        jsonEncode({
          'models': const <String>[],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );

      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      expect(cfg.models['one']!.provider, testProvider);
    });

    test('a broken overlay model file falls back to the downloaded one', () {
      writeBase();
      // The overlay file wins the alias but cannot be parsed, so it contributes
      // only a warning. The model must not disappear with it: a half-written
      // user file should degrade to the shipped list, not take the model away.
      writeModel(overlay, 'one', jsonEncode({'no_id': true}));

      final (cfg, warnings) = load();
      expect(cfg.models['one']!.id, 'one-base');
      expect(
        warnings.where((w) => w.startsWith('Overlay: ')),
        hasLength(1),
      );
    });

    test('a model no layer resolves is warned once, not once per layer', () {
      writeBase();
      // The provider claims an alias neither layer has a file for. The merged
      // provider list mentions it exactly once, so the warning does too.
      writeProvider(
        base,
        testProvider,
        jsonEncode({
          'models': ['one', 'ghost'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );

      final (cfg, warnings) = load();
      expect(cfg.models.keys, ['one']);
      expect(
        warnings.where(
          (w) => w.contains('$kVoiceConfigModelsDir/ghost.json is missing'),
        ),
        hasLength(1),
      );
    });
  });

  group('the voice entry codec', () {
    test('voiceFromEntry reads all three accepted shapes', () {
      expect(voiceFromEntry('Charon', 'Charon').voice?.id, 'Charon');
      expect(voiceFromEntry('bf_emma', {'name': 'Emma'}).voice?.id, 'bf_emma');
      final explicit = voiceFromEntry('Alice', {
        'id': 'c536',
        'gender': 'female',
      }).voice;
      expect(explicit?.id, 'c536');
      expect(explicit?.gender, VoiceGender.female);
    });

    test('voiceFromEntry reports why an entry is unusable', () {
      final bad = voiceFromEntry('Typo', {'idd': 'nope'});
      expect(bad.voice, isNull);
      expect(bad.problem, isNotNull);
    });

    test('voiceEntryJson round-trips a voice through voiceFromEntry', () {
      for (final voice in const [
        Voice(id: 'Charon'),
        Voice(id: 'bf_emma', name: 'Emma'),
        Voice(id: 'c536', gender: VoiceGender.female),
      ]) {
        final encoded = voiceEntryJson(voice.id, voice);
        final decoded = voiceFromEntry(voice.id, encoded).voice;
        expect(decoded, isNotNull);
        expect(decoded!.id, voice.id);
        expect(decoded.name, voice.name);
        expect(decoded.gender, voice.gender);
      }
    });

    test('voiceEntryJson omits an id that repeats the key', () {
      expect(voiceEntryJson('Charon', const Voice(id: 'Charon')), isEmpty);
    });

    test('canonicalVoiceEntryJson always states the id and never a name', () {
      expect(
        canonicalVoiceEntryJson(const Voice(id: 'Charon', name: 'Charon')),
        {'id': 'Charon'},
      );
      expect(
        canonicalVoiceEntryJson(
          const Voice(id: 'bf_emma', name: 'Emma', gender: VoiceGender.female),
        ),
        {'id': 'bf_emma', 'gender': 'female'},
      );
    });

    test('readModelJson prefers the overlay and falls back to the base', () {
      final dir = Directory.systemTemp.createTempSync('tts_config_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      void write(String layer, String alias, String contents) {
        final file = File(
          '${dir.path}${Platform.pathSeparator}$layer'
          '${Platform.pathSeparator}$kVoiceConfigModelsDir'
          '${Platform.pathSeparator}$alias.json',
        );
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(contents);
      }

      write('.', 'one', '{"id":"one-base"}');
      expect(readModelJson(dir.path, 'one')!['id'], 'one-base');

      write(kVoiceConfigOverlayDirName, 'one', '{"id":"one-overlay"}');
      expect(readModelJson(dir.path, 'one')!['id'], 'one-overlay');

      expect(readModelJson(dir.path, 'absent'), isNull);
    });
  });
}
