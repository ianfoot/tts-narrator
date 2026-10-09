import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/voice_config.dart';
import 'package:tts_narrator_core/src/config/voice_config_io.dart';
import 'package:tts_narrator_core/src/config/voice_config_queries.dart';
import 'package:tts_narrator_core/src/narration/audio_format.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';

import 'support/config_fixture.dart';
import 'support/fake_provider.dart';

void main() {
  group('loadVoiceConfig', () {
    late ConfigFixture fx;
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tts_config_test_');
      fx = ConfigFixture(dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    String at(String dirName, String file) => fx.at(dirName, file);

    void writeRegistry(String contents) => fx.writeRegistry(contents);

    void writeProvider(String name, String contents) =>
        fx.writeProvider(name, contents);

    void writeModel(String alias, String contents) =>
        fx.writeModel(alias, contents);

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

    /// Writes [json] as the one and only model `m` and returns its profile,
    /// ignoring any warning. For the tests whose subject is what a
    /// well-formed model file yields.
    TtsModelProfile loadProfile(String json) {
      writeClaimingProvider(testProvider, models: ['m']);
      writeModel('m', json);
      return load().$1.models['m']!;
    }

    /// As [loadProfile] but refusing to swallow a warning: a test that reads a
    /// field through here is also asserting the file was accepted whole.
    VoiceConfig loadConfig(String json) {
      writeClaimingProvider(testProvider, models: ['m']);
      writeModel('m', json);
      final (cfg, warnings) = load();
      expect(warnings, isEmpty);
      return cfg;
    }

    /// Writes [profile] as the one and only model `m`, then returns the JSON
    /// the writer actually put on disk for it.
    ///
    /// The mirror of [loadProfile] for the tests whose subject is the file
    /// rather than what the loader makes of it: those have to read the bytes
    /// back, and re-stating the provider wiring to get there says nothing
    /// about the model.
    Map<String, dynamic> writeAndReadModelFile(TtsModelProfile profile) {
      writeVoiceConfig(
        dir.path,
        VoiceConfig(
          providers: {
            testProvider: const ProviderConfig(
              name: testProvider,
              settings: {'base_url': testBaseUrl},
              models: ['m'],
            ),
          },
          models: {'m': profile},
        ),
      );
      return jsonDecode(
        File(at(kVoiceConfigModelsDir, 'm.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
    }

    /// The shape of every "the loader refuses this model file" case below: the
    /// file is written as the one and only model, and the warning it raises
    /// must name the reason. Declared here so each case is one line of data
    /// rather than six lines of arrange-act-assert.
    void rejection(String name, String json, String warning) {
      test(name, () {
        writeClaimingProvider(testProvider, models: ['m']);
        writeModel('m', json);
        final (cfg, warnings) = load();
        // Refused means dropped, not defaulted: a model the loader cannot
        // honour must not reach the app with a field silently invented.
        expect(cfg.models['m'], isNull);
        expect(warnings.first, contains(warning));
      });
    }

    test('parses per-model files into request profiles', () {
      writeClaimingProvider(testProvider, models: ['gemini']);
      writeModel(
        'gemini',
        '{"id":"google/gemini-3.1-flash-tts-preview","formats":["wav","mp3"],'
            '"prompt_style":true}',
      );
      final (cfg, warnings) = load();
      expect(cfg.models.containsKey('gemini'), isTrue);
      expect(cfg.models['gemini']!.id, 'google/gemini-3.1-flash-tts-preview');
      expect(cfg.models['gemini']!.formats, const [
        TtsAudioFormat.wav,
        TtsAudioFormat.mp3,
      ]);
      expect(cfg.models['gemini']!.promptStyle, isTrue);
      expect(cfg.models['gemini']!.provider, testProvider);
      expect(warnings, isEmpty);
    });

    group('output formats', () {
      test('reads the formats list in order, first one the default', () {
        final m = loadProfile('{"id": "a/b", "formats": ["wav", "mp3"]}');
        expect(m.formats, const [TtsAudioFormat.wav, TtsAudioFormat.mp3]);
        expect(m.defaultFormat, TtsAudioFormat.wav);
        expect(m.supportsFormat(TtsAudioFormat.mp3), isTrue);
      });

      test('drops a repeated format', () {
        final m = loadProfile('{"id": "a/b", "formats": ["mp3", "mp3"]}');
        expect(m.formats, const [TtsAudioFormat.mp3]);
      });

      test('accepts a model that serves mp3 only', () {
        // No shipped model has this shape -- Gemini is the only single-format
        // one and it is wav-only -- but a third-party endpoint that encodes mp3
        // and nothing else is a real possibility, so the shape stays legal.
        // Note there is no `wav_response_format` here: it would have nothing to
        // apply to, which is why declaring it without a wav format is rejected.
        final m = loadProfile('{"id": "a/b", "formats": ["mp3"]}');
        expect(m.formats, const [TtsAudioFormat.mp3]);
        expect(m.defaultFormat, TtsAudioFormat.mp3);
        expect(m.wavResponseFormat, TtsWavResponseFormat.wav);
      });

      // There is no default container. What a model can produce is a property
      // of its backend, so a file that stays silent about it is missing
      // information the app cannot invent.
      rejection(
        'skips a model that names no formats',
        '{"id": "a/b"}',
        'needs a "formats" list',
      );

      // A model we cannot serve audio for is worse than no model at all, so
      // it is dropped with a warning rather than quietly falling back.
      rejection(
        'skips a model naming a format nobody can produce',
        '{"id": "a/b", "formats": ["opus"]}',
        '"formats"',
      );

      rejection(
        'skips a model with an empty formats list',
        '{"id": "a/b", "formats": []}',
        '"formats"',
      );

      rejection(
        'skips a model whose formats value is not a list',
        '{"id": "a/b", "formats": "mp3"}',
        '"formats"',
      );

      test('writes the formats list back out', () {
        final json = writeAndReadModelFile(
          const TtsModelProfile(
            alias: 'm',
            id: 'a/b',
            formats: [TtsAudioFormat.wav, TtsAudioFormat.mp3],
            provider: testProvider,
          ),
        );
        expect(json['formats'], ['wav', 'mp3']);
        // `wav_response_format` defaults to `wav`, so it stays out of the file
        // rather than being written as redundant as an explicit `pcm` would be.
        expect(json.containsKey('wav_response_format'), isFalse);

        final (cfg, warnings) = load();
        expect(warnings, isEmpty);
        expect(cfg.models['m']!.formats, const [
          TtsAudioFormat.wav,
          TtsAudioFormat.mp3,
        ]);
      });

      test('writes an explicit wav_response_format back out', () {
        final json = writeAndReadModelFile(
          const TtsModelProfile(
            alias: 'm',
            id: 'a/b',
            formats: [TtsAudioFormat.wav],
            wavResponseFormat: TtsWavResponseFormat.pcm,
            provider: testProvider,
          ),
        );
        expect(json['wav_response_format'], 'pcm');
        expect(
          load().$1.models['m']!.wavResponseFormat,
          TtsWavResponseFormat.pcm,
        );
      });
    });

    group('wav_response_format', () {
      test('defaults to a wav container when the key is absent', () {
        expect(
          loadProfile('{"id":"a/b","formats":["wav"]}').wavResponseFormat,
          TtsWavResponseFormat.wav,
        );
      });

      test('reads pcm as the wav wire value', () {
        expect(
          loadProfile(
            '{"id":"a/b","formats":["wav"],"wav_response_format":"pcm"}',
          ).wavResponseFormat,
          TtsWavResponseFormat.pcm,
        );
      });

      rejection(
        'rejects a non-string',
        '{"id":"a/b","formats":["wav"],"wav_response_format":3}',
        '"wav_response_format" must be a string',
      );

      rejection(
        'rejects an unknown wire value',
        '{"id":"a/b","formats":["wav"],"wav_response_format":"flac"}',
        '"wav_response_format"',
      );

      // Self-contradictory: the key only names the wire value used for a wav
      // request, so a model that never gets asked for one would carry a
      // setting that can never be used.
      rejection(
        'rejects declaring it for a model that cannot produce wav',
        '{"id":"a/b","formats":["mp3"],"wav_response_format":"pcm"}',
        'does not include "wav"',
      );
    });

    group('speed capability', () {
      test('defaults to unsupported when the key is absent', () {
        expect(
          loadProfile('{"id":"x/y","formats":["wav"]}').supportsSpeed,
          isFalse,
        );
      });

      test('reads the opt-in flag', () {
        expect(
          loadProfile('{"id":"x/y","formats":["wav"],"speed":true}')
              .supportsSpeed,
          isTrue,
        );
        expect(
          loadProfile('{"id":"x/y","formats":["wav"],"speed":false}')
              .supportsSpeed,
          isFalse,
        );
      });

      rejection(
        'rejects a non-bool',
        '{"id":"x/y","formats":["wav"],"speed":"yes"}',
        '"speed" must be a bool',
      );
    });

    group('language table', () {
      const kokoroJson =
          '{"id":"hexgrad/kokoro-82m","formats":["wav"],"sends_language":true,'
          '"default_language":"b","languages":{"b":"British English",'
          '"j":"Japanese"}}';

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
        final cfg = loadConfig('{"id":"x/y","formats":["wav"]}');
        expect(cfg.models['m']!.sendsLanguageField, isFalse);
        expect(cfg.languagesFor('m'), isEmpty);
        expect(cfg.defaultLanguageFor('m'), isNull);
      });

      rejection(
        'rejects a non-bool sends_language',
        '{"id":"x/y","formats":["wav"],"sends_language":"yes"}',
        '"sends_language" must be a bool',
      );

      rejection(
        'rejects a default_language the table does not declare',
        '{"id":"x/y","formats":["wav"],"languages":{"b":"British"},'
            '"default_language":"z"}',
        '"default_language" is "z"',
      );

      rejection(
        'rejects a blank language label',
        '{"id":"x/y","formats":["wav"],"languages":{"b":""}}',
        '"languages"',
      );
    });

    group('voice design', () {
      const json =
          '{"id":"mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16",'
          '"formats":["wav"],"sends_instruct":true,"sends_voice":false,'
          '"default_instruct":"A calm, low British male narrator."}';

      TtsModelProfile loadProfile(String modelJson) =>
          loadConfig(modelJson).models['m']!;

      test('reads the capability and its default prose', () {
        final profile = loadProfile(json);
        expect(profile.sendsInstructField, isTrue);
        expect(profile.defaultInstruct, 'A calm, low British male narrator.');
        expect(profile.sendsVoiceField, isFalse);
      });

      test('a model with neither key reads as absent, not empty', () {
        final profile = loadProfile('{"id":"x/y","formats":["wav"]}');
        expect(profile.sendsInstructField, isFalse);
        expect(profile.defaultInstruct, isNull);
      });

      rejection(
        'rejects a non-bool sends_instruct',
        '{"id":"x/y","formats":["wav"],"sends_instruct":"yes"}',
        '"sends_instruct" must be a bool',
      );

      rejection(
        'rejects a non-string default_instruct',
        '{"id":"x/y","formats":["wav"],"default_instruct":42}',
        '"default_instruct" must be a string',
      );
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
        writeModel('one', '{"id":"x/one","formats":["wav"]}');
        writeModel('two', '{"id":"x/two","formats":["wav"]}');

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

      test(
        'rejects a models entry that is neither a list nor a platform map',
        () {
          writeRegistry('{"providers":["alpha"]}');
          writeProvider('alpha', '{"models":"one","settings":{}}');
          final (_, warnings) = load();
          expect(warnings.join('\n'), contains('"models" must be a list'));
        },
      );
    });

    group('per-platform provider models', () {
      // A provider file may key its models by platform instead of listing them
      // flat, which is how a provider that ships everywhere -- config.json is one
      // global registry, so providers/*.json lands on every platform -- can say
      // which of its models each platform may actually serve.

      test('a bare list serves every platform', () {
        for (final tag in [
          kPlatformTagMacos,
          kPlatformTagLinux,
          kPlatformTagWindows,
        ]) {
          writeRegistry('{"providers":["alpha"]}');
          writeProvider('alpha', '{"models":["one"],"settings":{}}');
          writeModel('one', '{"id":"x/one","formats":["wav"]}');

          final (cfg, warnings) = loadVoiceConfig(dir.path, platformTag: tag);
          expect(warnings, isEmpty, reason: 'on $tag');
          expect(cfg.models['one']!.provider, 'alpha', reason: 'on $tag');
        }
      });

      test('a platform map serves only the named platform', () {
        for (final tag in [
          kPlatformTagMacos,
          kPlatformTagLinux,
          kPlatformTagWindows,
        ]) {
          writeRegistry('{"providers":["alpha"]}');
          writeProvider(
            'alpha',
            '{"models":{"$kPlatformTagMacos":["mac_only"]},'
                '"settings":{}}',
          );
          writeModel('mac_only', '{"id":"x/mac","formats":["wav"]}');

          final (cfg, warnings) = loadVoiceConfig(dir.path, platformTag: tag);
          expect(warnings, isEmpty, reason: 'on $tag');
          if (tag == kPlatformTagMacos) {
            expect(
              cfg.models['mac_only']!.provider,
              'alpha',
              reason: 'on $tag',
            );
          } else {
            // The file is present but the platform may not claim the model, so
            // it is not loaded -- and, crucially, not warned about either.
            expect(
              cfg.models.containsKey('mac_only'),
              isFalse,
              reason: 'on $tag',
            );
          }
        }
      });

      test('a platform the map does not name serves nothing', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider(
          'alpha',
          '{"models":{"$kPlatformTagMacos":["mac_only"]},"settings":{}}',
        );

        final (cfg, warnings) = loadVoiceConfig(
          dir.path,
          platformTag: kPlatformTagLinux,
        );
        expect(warnings, isEmpty);
        expect(cfg.providers['alpha']!.models, isEmpty);
      });

      test('an explicitly empty platform list serves nothing', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider(
          'alpha',
          '{"models":{"$kPlatformTagMacos":["mac_only"],'
              '"$kPlatformTagLinux":[]},"settings":{}}',
        );
        writeModel('mac_only', '{"id":"x/mac","formats":["wav"]}');

        final (mac, macWarnings) = loadVoiceConfig(
          dir.path,
          platformTag: kPlatformTagMacos,
        );
        final (linux, linuxWarnings) = loadVoiceConfig(
          dir.path,
          platformTag: kPlatformTagLinux,
        );

        expect(macWarnings, isEmpty);
        expect(linuxWarnings, isEmpty);
        expect(mac.models['mac_only']!.provider, 'alpha');
        expect(linux.providers['alpha']!.models, isEmpty);
      });

      test('each platform entry is validated as a list of aliases', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider(
          'alpha',
          '{"models":{"$kPlatformTagLinux":"one"},"settings":{}}',
        );
        final (_, warnings) = loadVoiceConfig(
          dir.path,
          platformTag: kPlatformTagLinux,
        );
        expect(warnings.join('\n'), contains('"models" must be a list'));
      });

      test('an unknown platform key is rejected by name', () {
        // A misspelled tag is the failure mode worth guarding: it reads the same
        // as "serves nothing", so the provider silently claims no models on
        // every platform -- including the one the key was written for -- and
        // nothing anywhere reports why.
        writeRegistry('{"providers":["alpha"]}');
        writeProvider(
          'alpha',
          '{"models":{"macOS":["mac_only"]},"settings":{}}',
        );
        writeModel('mac_only', '{"id":"x/mac","formats":["wav"]}');

        for (final tag in [kPlatformTagMacos, null]) {
          final (cfg, warnings) = loadVoiceConfig(
            dir.path,
            platformTag: tag,
          );
          final joined = warnings.join('\n');
          expect(joined, contains('Skipped provider "alpha"'));
          expect(joined, contains('unknown platform "macOS"'));
          expect(
            cfg.providers.containsKey('alpha'),
            isFalse,
            reason: 'on ${tag ?? 'an untagged read'}',
          );
        }
      });

      test('an empty alias in a platform entry is rejected', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider(
          'alpha',
          '{"models":{"$kPlatformTagLinux":["  "]},"settings":{}}',
        );
        final (_, warnings) = loadVoiceConfig(
          dir.path,
          platformTag: kPlatformTagLinux,
        );
        expect(warnings.join('\n'), contains('"models" must hold non-empty'));
      });

      test('no platform tag unions every platform entry', () {
        // A caller inspecting the config as data has no platform in hand. The
        // union keeps such a caller seeing the whole picture -- and keeps the
        // shipped-config test, which loads without a tag, resolving the map.
        writeRegistry('{"providers":["alpha"]}');
        writeProvider(
          'alpha',
          '{"models":{"$kPlatformTagMacos":["mac_only"],'
              '"$kPlatformTagLinux":["linux_only"]},"settings":{}}',
        );
        writeModel('mac_only', '{"id":"x/mac","formats":["wav"]}');
        writeModel('linux_only', '{"id":"x/linux","formats":["wav"]}');

        final (cfg, warnings) = loadVoiceConfig(dir.path);
        expect(warnings, isEmpty);
        expect(cfg.providers['alpha']!.models, ['mac_only', 'linux_only']);
      });

      test('a shared alias in two platform entries appears once', () {
        writeRegistry('{"providers":["alpha"]}');
        writeProvider(
          'alpha',
          '{"models":{"$kPlatformTagMacos":["shared","mac_only"],'
              '"$kPlatformTagLinux":["shared","linux_only"]},"settings":{}}',
        );

        final (cfg, _) = loadVoiceConfig(dir.path);
        expect(cfg.providers['alpha']!.models, [
          'shared',
          'mac_only',
          'linux_only',
        ]);
      });

      test('a per-platform gate also silences the missing-model warning', () {
        // The regression this shape exists for: on Linux the download step
        // fetches providers/local.json but not its macOS-only model files, so a
        // provider claiming them unconditionally reads as broken.
        writeRegistry('{"providers":["alpha"]}');
        writeProvider(
          'alpha',
          '{"models":{"$kPlatformTagMacos":["mac_only"]},"settings":{}}',
        );

        final (unaware, unawareWarnings) = loadVoiceConfig(dir.path);
        expect(unawareWarnings.join('\n'), contains('lists model "mac_only"'));
        expect(unaware.providers['alpha']!.models, ['mac_only']);

        final (linux, linuxWarnings) = loadVoiceConfig(
          dir.path,
          platformTag: kPlatformTagLinux,
        );
        expect(linuxWarnings, isEmpty);
      });

      test('a bare provider file is unaffected by the platform', () {
        // The backward-compatibility half of the same rule: the flat shape keeps
        // meaning "every platform", so no shipped provider needs rewriting.
        writeRegistry('{"providers":["alpha"]}');
        writeProvider('alpha', '{"models":["one"],"settings":{}}');
        writeModel('one', '{"id":"x/one","formats":["wav"]}');

        final (mac, _) = loadVoiceConfig(
          dir.path,
          platformTag: kPlatformTagMacos,
        );
        final (linux, _) = loadVoiceConfig(
          dir.path,
          platformTag: kPlatformTagLinux,
        );
        expect(mac.providers['alpha']!.models, ['one']);
        expect(linux.providers['alpha']!.models, ['one']);
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

    const baseUrlSettings = {'base_url': testBaseUrl};

    /// The one provider most of these tests speak through, claiming [models].
    /// [settings] stays empty where a test's subject is what the writer adds on
    /// its own, so the provider must not supply a settings block of its own.
    ProviderConfig claiming(
      List<String> models, {
      Map<String, String> settings = const {},
    }) => ProviderConfig(name: testProvider, settings: settings, models: models);

    /// Writes [config] out and reads it straight back.
    ///
    /// Every assertion in this group is about a round trip — what the writer
    /// put on disk, and what the loader then makes of it — so naming the pair
    /// once leaves each test on the half it is actually about.
    (VoiceConfig, List<String>) roundTrip(VoiceConfig config) {
      writeVoiceConfig(dir.path, config);
      return loadVoiceConfig(dir.path);
    }

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
      roundTrip(
          VoiceConfig(
            providers: {
              testProvider: claiming(
                const ['fast', 'plain'],
                settings: baseUrlSettings,
              ),
            },
            models: {
              'fast': const TtsModelProfile(
                alias: 'fast',
                id: 'x/y',
                formats: [TtsAudioFormat.wav],
                supportsSpeed: true,
                provider: testProvider,
              ),
              'plain': const TtsModelProfile(
                alias: 'plain',
                id: 'x/z',
                formats: [TtsAudioFormat.wav],
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
      roundTrip(
          VoiceConfig(
            providers: {
              testProvider: claiming(
                const ['kokoro'],
                settings: baseUrlSettings,
              ),
            },
            models: {
              'kokoro': const TtsModelProfile(
                alias: 'kokoro',
                id: 'hexgrad/kokoro-82m',
                formats: [TtsAudioFormat.wav],
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
      roundTrip(
        VoiceConfig(
          providers: {testProvider: claiming(const ['one'])},
          models: {
            'one': const TtsModelProfile(
              alias: 'one',
              id: 'x/one',
              formats: [TtsAudioFormat.wav],
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

    test(
      'voice design round-trips, and an ordinary model emits no instruct keys',
      () {
        roundTrip(
          VoiceConfig(
            providers: {testProvider: claiming(const ['one', 'two'])},
            models: {
              'one': const TtsModelProfile(
                alias: 'one',
                id: 'mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16',
                formats: [TtsAudioFormat.wav],
                sendsInstructField: true,
                defaultInstruct: 'A calm, low British male narrator.',
                provider: testProvider,
              ),
              'two': const TtsModelProfile(
                alias: 'two',
                id: 'x/two',
                formats: [TtsAudioFormat.wav],
                provider: testProvider,
              ),
            },
          ),
        );

        final designed = jsonDecode(
          File(at(kVoiceConfigModelsDir, 'one.json')).readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(designed['sends_instruct'], isTrue);
        expect(
          designed['default_instruct'],
          'A calm, low British male narrator.',
        );

        final plain = jsonDecode(
          File(at(kVoiceConfigModelsDir, 'two.json')).readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(plain.containsKey('sends_instruct'), isFalse);
        expect(plain.containsKey('default_instruct'), isFalse);

        final (cfg, warnings) = loadVoiceConfig(dir.path);
        expect(warnings, isEmpty);
        expect(cfg.models['one']!.sendsInstructField, isTrue);
        expect(
          cfg.models['one']!.defaultInstruct,
          'A calm, low British male narrator.',
        );
      },
    );

    test('round-trips the whole tree back into an equal config', () {
      final original = VoiceConfig(
        providers: {
          testProvider: claiming(const ['one'], settings: baseUrlSettings),
        },
        models: {
          'one': const TtsModelProfile(
            alias: 'one',
            id: 'x/one',
            formats: [TtsAudioFormat.wav],
            provider: testProvider,
          ),
        },
      );
      final (reloaded, warnings) = roundTrip(original);
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
      final (reloaded, warnings) = roundTrip(
        VoiceConfig(
          providers: {testProvider: claiming(const [])},
          models: {
            'stray': const TtsModelProfile(
              alias: 'stray',
              id: 'x/stray',
              formats: [TtsAudioFormat.wav],
              provider: testProvider,
            ),
          },
        ),
      );
      expect(warnings, isEmpty);
      expect(reloaded.providers[testProvider]!.models, ['stray']);
      expect(reloaded.models['stray'], isNotNull);
    });
  });

  group('the user overlay', () {
    late ConfigFixture fx;
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tts_config_test_');
      fx = ConfigFixture(dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    /// The config root, where the downloaded starter files live.
    const base = ConfigFixture.base;

    /// The overlay root, where everything the user authors lands.
    const overlay = ConfigFixture.overlay;

    void writeRegistry(String contents) => fx.writeRegistry(contents);

    /// The overlay's own registry: a second `config.json`, which the loader
    /// merges with the base rather than the overlay replacing it.
    void writeOverlayRegistry(String contents) =>
        fx.writeRegistry(contents, overlay);

    /// A file inside [layer]'s providers or models directory. [layer] is either
    /// the config root or the overlay root, so the two call sites below read as
    /// `writeModel(base, ...)` / `writeModel(overlay, ...)` rather than as
    /// duplicated path arithmetic.
    void writeProvider(String layer, String name, String contents) =>
        fx.writeProvider(name, contents, layer);

    void writeModel(String layer, String alias, String contents) =>
        fx.writeModel(alias, contents, layer);

    String modelJson(String id, {String? defaultVoice}) => jsonEncode({
      'id': id,
      'formats': ['wav'],
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
            settingsByProvider[provider] ?? '{"base_url":"$testBaseUrl"}',
          ),
        }),
      );
      for (final alias in models) {
        writeModel(base, alias, modelJson('$alias-base'));
      }
    }

    (VoiceConfig, List<String>) load() => loadVoiceConfig(dir.path);

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

    test('an overlay model the base provider still claims needs no overlay '
        'registry', () {
      writeBase();
      // The user only ever authored a model file, nothing else.
      writeModel(overlay, 'one', modelJson('one-overlay'));
      final (cfg, _) = load();
      expect(cfg.models['one']!.id, 'one-overlay');
    });

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
      writeOverlayRegistry(
        jsonEncode({
          'providers': ['alpha'],
        }),
      );

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
      writeOverlayRegistry(
        jsonEncode({
          'providers': [testProvider],
        }),
      );

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
      writeRegistry(
        jsonEncode({
          'providers': ['beta'],
        }),
      );
      writeProvider(
        overlay,
        'alpha',
        jsonEncode({
          'models': ['two'],
          'settings': jsonDecode('{"base_url":"$testBaseUrl"}'),
        }),
      );
      writeModel(overlay, 'two', modelJson('two-overlay'));
      writeOverlayRegistry(
        jsonEncode({
          'providers': ['alpha'],
        }),
      );

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
      expect(warnings.where((w) => w.startsWith('Overlay: ')), hasLength(1));
      expect(warnings, hasLength(1));
    });

    test('voices_editable is read from the file', () {
      writeBase();
      writeModel(
        base,
        'one',
        jsonEncode({
          'id': 'one-base',
          'formats': ['wav'],
          'voices_editable': true,
        }),
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
        jsonEncode({
          'id': 'one-base',
          'formats': ['wav'],
          'voices_editable': 'yes',
        }),
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
      expect(warnings.where((w) => w.startsWith('Overlay: ')), hasLength(1));
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

    test('an id-keyed voice survives the empty object it is written as', () {
      // A voice with no name and no gender, keyed by its own id, has nothing
      // left to say, so it is written as "Charon": {} -- a shape no shipped file
      // contains, and the one a model shipped as a bare id list becomes the
      // moment anything rewrites its config. It reloads only because an empty
      // map states no id for voiceFromEntry to reject and names no field
      // outside the schema, so both of its checks pass on nothing at all. Pinned
      // here so tightening either check is a deliberate act rather than a silent
      // way to drop every voice in the file.
      final encoded = voiceEntryJson('Charon', const Voice(id: 'Charon'));
      expect(encoded, isEmpty);

      final decoded = voiceFromEntry('Charon', encoded);
      expect(decoded.problem, isNull);
      expect(decoded.voice, isNotNull);
      expect(decoded.voice!.id, 'Charon');
      expect(decoded.voice!.name, isNull);
      expect(decoded.voice!.gender, isNull);
    });
  });
}
