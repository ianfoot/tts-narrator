import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator/src/gui/controller/api_key_store.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/controller/controller_errors.dart'
    show CannotOpenTextFile, NoVoiceSelected;
import 'package:tts_narrator/src/gui/controller/run_controller.dart'
    show NarrationBlockReason;
import 'package:tts_narrator/src/gui/controller/settings_controller.dart'
    show ApiKeySource, SettingsController;
import 'package:tts_narrator/src/gui/theme/app_tokens.dart' show AppThemeMode;
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../support/fake_tts_provider.dart';
import '../support/settings_fixtures.dart' as fixtures;

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_controller_test_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Writes the shared grouped config body onto the registry layout, against
  /// this group's config dir.
  void writeConfig(Map<String, Object?> body) =>
      fixtures.writeConfig(configDir, body);

  /// [environment] defaults to empty so no test depends on what the host shell
  /// exports; pass a map to exercise `${ENV}` reference resolution.
  AppController makeController({
    SpeechClient? client,
    ApiKeyStore? apiKeyStore,
    Map<String, String>? environment,
  }) => AppController(
    loader: UserVoiceConfigLoader(
      configDir: configDir,
      environment: environment ?? const {},
    ),
    apiKeyStore: apiKeyStore,
    client: client,
  );

  /// An [ApiKeyStore] that has already completed its startup [ApiKeyStore.load]
  /// (against the in-memory mock) so the cached key for [provider] is
  /// deterministically [key]. A null [key] means "nothing stored" for that
  /// provider; any other provider's entry is cleared by the mock reset too.
  Future<ApiKeyStore> storeLoadedWith(
    String? key, {
    String provider = 'alpha',
  }) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'tts-narrator.api_key.$provider': ?key,
    });
    final store = ApiKeyStore();
    await store.load();
    return store;
  }

  /// Writes the starter fish config (a fish model file claimed by a provider)
  /// mirroring the shipped voice-config layout) so the controller preselects
  /// fish with its default voice, as it does after the first-run download.
  void writeFishConfig() {
    writeConfig({
      'providers': {
        'alpha': {
          'base_url': 'https://vendor.example/api/v1',
          'api_key': 'sk-test',
        },
      },
      'models': {
        'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
      },
      'defaults': {'fish': 'British Female Narrator'},
      'voices': {
        'fish': {'British Female Narrator': '89f41ea230034706881f85a8227d6ab9'},
      },
    });
  }

  /// As [writeFishConfig], but the model declares `prompt_style`, which is
  /// what derives the prompt-controls portion of the model-options spec.
  void writePromptStyleFishConfig() {
    writeConfig({
      'providers': {
        'alpha': {
          'base_url': 'https://vendor.example/api/v1',
          'api_key': 'sk-test',
        },
      },
      'models': {
        'fish': {
          'id': 'fish-audio/s2.1-pro-free:free',
          'format': 'mp3',
          'prompt_style': true,
        },
      },
      'defaults': {'fish': 'British Female Narrator'},
      'voices': {
        'fish': {'British Female Narrator': '89f41ea230034706881f85a8227d6ab9'},
      },
    });
  }

  group('cold start', () {
    test('boots an empty, untitled document with no model configured', () {
      final c = makeController();
      expect(c.text, isEmpty);
      // A never-saved document has no file name; the untitled placeholder is
      // UI copy and is resolved in the widget layer via `documentNameX.display`.
      expect(c.documentName, isNull);
      expect(c.dirty, isFalse);
      expect(c.wordCount, 0);
      expect(c.charCount, 0);
      expect(c.plannedSegments, isEmpty);
      // No config models -> no model to select, so
      // narration is unavailable until a config (or the starter download)
      // provides one.
      expect(c.profile, isNull);
      expect(c.modelAlias, isNull);
      expect(c.voice, '');
      expect(c.voiceLabel, isNull);
    });

    test('a missing config file yields no model (no compiled fallback)', () {
      final c = AppController(
        loader: UserVoiceConfigLoader(configDir: '${dir.path}/nope'),
      );
      expect(c.profile, isNull);
      expect(c.modelAlias, isNull);
      expect(c.voice, '');
    });
  });

  group('document', () {
    test('setText replaces the text and marks the document dirty', () {
      final c = makeController();
      c.setText('The rain fell on the quiet street.');
      expect(c.text, 'The rain fell on the quiet street.');
      expect(c.dirty, isTrue);
      expect(c.wordCount, 7);
      expect(c.charCount, 'The rain fell on the quiet street.'.length);
      // No paragraphs -> no plan yet.
      expect(c.plannedSegments, hasLength(1));
    });

    test('setText with identical value is ignored', () {
      final c = makeController();
      c.setText('Hello');
      expect(c.dirty, isTrue);
      // Editing does not name the document; it stays null until first save.
      expect(c.documentName, isNull);
    });

    test(
      'loadFromFile reads the file, sets the path, clears the dirty flag',
      () {
        writeFishConfig();
        final story = File('${dir.path}/story.txt')
          ..writeAsStringSync('Once upon a time there was a very long story.');
        final c = makeController();
        c.loadFromFile(story.path);
        expect(c.text, 'Once upon a time there was a very long story.');
        expect(c.documentPath, story.absolute.path);
        expect(c.documentName, 'story.txt');
        expect(c.dirty, isFalse);
        expect(c.narrateBlockReason(), isNull);
      },
    );

    test('loadFromFile throws when the file is missing', () {
      final c = makeController();
      // Typed, not a raw FileSystemException: the widget layer matches on the
      // type to pick the localized message.
      expect(
        () => c.loadFromFile('${dir.path}/missing.txt'),
        throwsA(
          isA<CannotOpenTextFile>().having(
            (e) => e.path,
            'path',
            '${dir.path}/missing.txt',
          ),
        ),
      );
    });
  });

  group('save', () {
    test(
      'saveTo writes the text, adopts the path and clears the dirty flag',
      () {
        final c = makeController()
          ..setText('Saved text. Enough words to count.');
        final target = File('${dir.path}/saved.txt');
        c.saveTo(target.path);
        expect(File(target.absolute.path).readAsStringSync(), c.text);
        expect(c.documentPath, target.absolute.path);
        expect(c.documentName, 'saved.txt');
        expect(c.dirty, isFalse);
      },
    );

    test('saveAs picks a location, writes and adopts it', () async {
      final c = makeController()..setText('Via save as. Enough words.');
      c.saveLocationPicker = () async => '${dir.path}/picked.txt';
      await c.saveAs();
      expect(File('${dir.path}/picked.txt').readAsStringSync(), c.text);
      expect(c.documentPath, '${dir.path}/picked.txt');
      expect(c.dirty, isFalse);
    });

    test('saveAs with a cancelled picker leaves the path untouched', () async {
      final c = makeController()..setText('Not saved. Enough words.');
      c.saveLocationPicker = () async => null;
      await c.saveAs();
      expect(c.documentPath, isNull);
      expect(c.dirty, isTrue);
    });

    test('save on a titled document writes without picking', () async {
      final c = makeController()..setText('Direct save. Enough words.');
      final target = File('${dir.path}/direct.txt');
      c.saveTo(target.path);
      c.setText('Updated. Enough words to narrate.');
      var picked = false;
      c.saveLocationPicker = () async {
        picked = true;
        return null;
      };
      await c.save();
      expect(picked, isFalse);
      expect(File(target.absolute.path).readAsStringSync(), c.text);
      expect(c.dirty, isFalse);
    });
  });

  group('buildConfig', () {
    test('narrates from in-memory text with an untitled input path', () {
      writeFishConfig();
      final c = makeController()..setText('Hello world. Some more words here.');
      final cfg = c.buildConfig();
      expect(cfg.sourceText, 'Hello world. Some more words here.');
      expect(cfg.inputPath, 'untitled.txt');
      expect(cfg.profile.alias, 'fish');
      expect(cfg.voice, '89f41ea230034706881f85a8227d6ab9');
      expect(cfg.apiKey, 'sk-test');
      expect(cfg.pricing, freePricing);
    });

    test('documents use the real path for output naming', () async {
      writeFishConfig();
      final story = File('${dir.path}/my chapter.txt')
        ..writeAsStringSync('A chapter with enough words to narrate.');
      final c = makeController()..loadFromFile(story.path);
      final cfg = c.buildConfig();
      expect(cfg.sourceText, 'A chapter with enough words to narrate.');
      expect(cfg.inputPath, story.absolute.path);
      expect(inputStem(cfg.inputPath), 'my_chapter');
    });

    test('sendWholeFile flows through to the narration config', () async {
      writeFishConfig();
      final c = makeController()..setText('One.\n\nTwo.');
      expect(c.buildConfig().sendWholeFile, isFalse);
      c.sendWholeFile = true;
      final cfg = c.buildConfig();
      expect(cfg.sendWholeFile, isTrue);
      // Whole-file mode plans a single segment containing the whole text.
      expect(c.plannedSegments, ['One.\n\nTwo.']);
    });

    test('wholeFileAvailable tracks the 60k character cap', () {
      writeConfig({});
      final c = makeController();
      // Blank and short documents stay under the cap.
      expect(c.wholeFileAvailable, isTrue);
      c.setText('   \n\n  ');
      expect(c.wholeFileAvailable, isTrue);
      c.setText('x');
      expect(c.wholeFileAvailable, isTrue);

      c.setText(List.filled(maxWholeFileLength, 'x').join());
      expect(c.wholeFileAvailable, isTrue);

      c.setText(List.filled(maxWholeFileLength + 1, 'x').join());
      expect(c.wholeFileAvailable, isFalse);
    });

    test(
      'a document that grows past the cap auto-disables whole-file mode',
      () {
        writeConfig({});
        final c = makeController()..setText('Small.');
        c.sendWholeFile = true;
        expect(c.sendWholeFile, isTrue);

        // Growing past the cap clears the toggle so no giant single segment can
        // be scheduled behind a hidden switch.
        c.setText(List.filled(maxWholeFileLength + 1, 'x').join());
        expect(c.sendWholeFile, isFalse);
        expect(c.plannedSegments.single, hasLength(maxWholeFileLength + 1));
      },
    );

    test('empty text in whole-file mode plans no segments', () {
      writeConfig({});
      final c = makeController()..setText('Hello.');
      c.sendWholeFile = true;
      c.setText('');
      expect(c.plannedSegments, isEmpty);
    });

    test('throws NoVoiceSelected when the model has no selected voice', () {
      writeConfig({
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
            'prompt_style': true,
          },
        },
      });
      final c = makeController();
      c.changeModel('gemini');
      expect(c.voice, isEmpty);
      expect(() => c.buildConfig(), throwsA(isA<NoVoiceSelected>()));
    });
  });

  group('API key secure-store fallback', () {
    setUp(() {
      // Every test in this file runs in the same isolate; reset the mock so a
      // stored key never leaks between tests. Mutable: the mock also accepts
      // writes from save/remove.
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    /// Writes the fish config whose alpha block references a `${ENV}`
    /// that is guaranteed absent — the exact double-click scenario the
    /// secure-store fallback exists for.
    void writeEnvRefFishConfig(String ref) {
      writeConfig({
        'providers': {
          'alpha': {'api_key': ref},
        },
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
        },
        'defaults': {'fish': 'British Female Narrator'},
        'voices': {
          'fish': {
            'British Female Narrator': '89f41ea230034706881f85a8227d6ab9',
          },
        },
      });
    }

    test(
      'an unresolvable \${ENV} ref falls back to the securely stored key',
      () async {
        writeEnvRefFishConfig(r'${TTS_NARRATOR_NOT_SET}');
        final c = AppController(
          loader: UserVoiceConfigLoader(
            configDir: configDir,
            environment: const {},
          ),
          apiKeyStore: await storeLoadedWith('sk-stored'),
        )..setText('A sentence.');
        final cfg = c.buildConfig();
        expect(cfg.apiKey, 'sk-stored');
        expect(c.apiKeySource, ApiKeySource.keychain);
      },
    );

    test('a config literal is the key when nothing is stored', () async {
      writeFishConfig(); // `api_key: sk-test` literal.
      final c = AppController(
        loader: UserVoiceConfigLoader(
          configDir: configDir,
          environment: const {},
        ),
        apiKeyStore: await storeLoadedWith(null),
      )..setText('A sentence.');
      final cfg = c.buildConfig();
      expect(cfg.apiKey, 'sk-test');
      expect(c.apiKeySource, ApiKeySource.config);
    });

    test(
      'a resolvable \${ENV} ref flows through and reads as environment',
      () async {
        writeEnvRefFishConfig(r'${HOME}');
        final c = AppController(
          loader: UserVoiceConfigLoader(
            configDir: configDir,
            environment: const {'HOME': '/home/test'},
          ),
          apiKeyStore: await storeLoadedWith('sk-stored'),
        )..setText('A sentence.');
        final cfg = c.buildConfig();
        expect(cfg.apiKey, 'sk-stored');
        expect(c.apiKeySource, ApiKeySource.keychain);
      },
    );

    test('a securely stored key overrides a config literal', () async {
      // Deliberate: the provider file arrives from a remote download, so a key
      // in it can be a pooled credential. A keychain entry was typed by this
      // user, so it wins.
      writeFishConfig(); // `api_key: sk-test` literal.
      final c = AppController(
        loader: UserVoiceConfigLoader(
          configDir: configDir,
          environment: const {},
        ),
        apiKeyStore: await storeLoadedWith('sk-stored'),
      )..setText('A sentence.');
      final cfg = c.buildConfig();
      expect(cfg.apiKey, 'sk-stored');
      expect(c.apiKeySource, ApiKeySource.keychain);
    });

    test(
      'a resolvable \${ENV} ref flows through and reads as environment',
      () async {
        writeEnvRefFishConfig(r'${HOME}');
        final c = AppController(
          loader: UserVoiceConfigLoader(
            configDir: configDir,
            environment: const {'HOME': '/home/test'},
          ),
          apiKeyStore: ApiKeyStore(),
        )..setText('A sentence.');
        final cfg = c.buildConfig();
        expect(cfg.apiKey, '/home/test');
        expect(c.apiKeySource, ApiKeySource.environment);
      },
    );

    test('the key never lands in providerSettings', () async {
      writeFishConfig(); // `api_key: sk-test` literal.
      final c = AppController(
        loader: UserVoiceConfigLoader(
          configDir: configDir,
          environment: const {},
        ),
        apiKeyStore: await storeLoadedWith('sk-stored'),
      )..setText('A sentence.');
      final settings = c.buildConfig().providerSettings;
      expect(
        settings.containsKey('api_key'),
        isFalse,
        reason:
            'the secret travels as NarrationConfig.apiKey, not as a setting',
      );
    });

    test('a run is never blocked when no key exists anywhere', () {
      // The load-bearing guarantee: whether a provider *needs* a key is the
      // server's judgement, so the app must not refuse to build a run. A null
      // apiKey means "send no Authorization header", not "error".
      writeEnvRefFishConfig(r'${TTS_NARRATOR_NOT_SET}');
      final c = AppController(
        loader: UserVoiceConfigLoader(
          configDir: configDir,
          environment: const {},
        ),
        apiKeyStore: ApiKeyStore(),
      )..setText('A sentence.');
      expect(() => c.buildConfig(), returnsNormally);
      expect(c.buildConfig().apiKey, isNull);
      expect(c.apiKeySource, ApiKeySource.missing);
    });

    test('saving/removing through the store flips the rail status', () async {
      writeEnvRefFishConfig(r'${TTS_NARRATOR_NOT_SET}');
      final c = AppController(
        loader: UserVoiceConfigLoader(
          configDir: configDir,
          environment: const {},
        ),
        apiKeyStore: await storeLoadedWith(null),
      );
      expect(c.apiKeySource, ApiKeySource.missing);
      await c.saveApiKey(' sk-stored ');
      expect(c.hasStoredApiKey, isTrue);
      expect(c.apiKeySource, ApiKeySource.keychain);
      expect(c.buildConfig().apiKey, 'sk-stored');
      await c.removeApiKey();
      expect(c.hasStoredApiKey, isFalse);
      expect(c.apiKeySource, ApiKeySource.missing);
    });
  });

  group('per-provider key store', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    /// Two providers, each claiming its own model, so switching model switches
    /// which provider the active model resolves to.
    void writeTwoProviderConfig() {
      writeConfig({
        'providers': {
          'alpha': {
            'models': ['fish'],
            'base_url': 'https://vendor.example/api/v1',
            'api_key': r'${VENDOR_API_KEY}',
          },
          'groq': {
            'models': ['gemini'],
            'base_url': 'https://api.groq.invalid',
            'api_key': r'${GROQ_API_KEY}',
          },
        },
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
          },
        },
        'defaults': {'fish': 'British Female Narrator', 'gemini': 'Charon'},
        'voices': {
          'fish': {
            'British Female Narrator': '89f41ea230034706881f85a8227d6ab9',
          },
        },
      });
    }

    test('a saved key is filed under the active provider only', () async {
      writeTwoProviderConfig();
      final c = AppController(
        loader: UserVoiceConfigLoader(
          configDir: configDir,
          environment: const {},
        ),
        apiKeyStore: await storeLoadedWith(null),
      );
      expect(c.profile?.provider, 'alpha');

      await c.saveApiKey('sk-test');
      expect(c.hasStoredApiKey, isTrue);

      // Read the store back independently: the secret must sit in alpha's
      // namespace and nowhere else.
      final reread = ApiKeyStore();
      await reread.load();
      expect(reread.value('alpha'), 'sk-test');
      expect(reread.value('groq'), isNull);
    });

    test('switching model switches which stored key is visible', () async {
      writeTwoProviderConfig();
      final c = AppController(
        loader: UserVoiceConfigLoader(
          configDir: configDir,
          environment: const {},
        ),
        apiKeyStore: await storeLoadedWith(null),
      );

      // Neither provider has a key yet, so the rail reports "Not set" for both.
      expect(c.hasStoredApiKey, isFalse);
      expect(c.apiKeySource, ApiKeySource.missing);

      await c.saveApiKey('sk-test');
      expect(c.hasStoredApiKey, isTrue);
      expect(c.apiKeySource, ApiKeySource.keychain);
      expect(c.buildConfig().apiKey, 'sk-test');

      // Switching to the other provider must not inherit alpha's key.
      c.changeModel('gemini');
      expect(c.profile?.provider, 'groq');
      expect(c.hasStoredApiKey, isFalse);
      expect(c.apiKeySource, ApiKeySource.missing);
      expect(c.buildConfig().apiKey, isNull);

      // Saving under groq leaves alpha's key intact.
      await c.saveApiKey('gsk-groq');
      expect(c.buildConfig().apiKey, 'gsk-groq');
      c.changeModel('fish');
      expect(c.hasStoredApiKey, isTrue);
      expect(c.buildConfig().apiKey, 'sk-test');

      // Removing under groq touches only groq's slot.
      c.changeModel('gemini');
      await c.removeApiKey();
      expect(c.hasStoredApiKey, isFalse);
      c.changeModel('fish');
      expect(c.hasStoredApiKey, isTrue);
    });

    test('saving with no model configured is a no-op', () async {
      final c = makeController();
      expect(c.profile, isNull);
      await expectLater(c.saveApiKey('sk-orphan'), completes);
      await expectLater(c.removeApiKey(), completes);
      expect(c.hasStoredApiKey, isFalse);
    });
  });

  group('api_key resolution', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    /// Writes a fish config whose only provider is [providerName], declaring
    /// exactly [settings]. The provider file's name is what the model resolves
    /// its provider to, so this also proves the name is not special-cased.
    void writeProviderConfig(
      String providerName,
      Map<String, String> settings,
    ) {
      writeConfig({
        'providers': {
          providerName: {...settings},
        },
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
        },
        'defaults': {'fish': 'British Female Narrator'},
        'voices': {
          'fish': {
            'British Female Narrator': '89f41ea230034706881f85a8227d6ab9',
          },
        },
      });
    }

    test(
      r'the shipped shape: a ${ENV} reference resolves from the environment',
      () async {
        // The shipped provider block carries `"api_key": "${VENDOR_API_KEY}"`.
        writeProviderConfig('alpha', {
          'base_url': 'https://vendor.example/api/v1',
          'api_key': r'${VENDOR_API_KEY}',
        });
        final c = makeController(
          environment: const {'VENDOR_API_KEY': 'sk-from-env'},
        )..setText('A sentence.');

        final cfg = c.buildConfig();
        expect(
          cfg.providerSettings['base_url'],
          'https://vendor.example/api/v1',
        );
        expect(cfg.apiKey, 'sk-from-env');
        expect(c.apiKeySource, ApiKeySource.environment);
      },
    );

    test(
      r'an unresolvable ${ENV} reference falls back to the stored key',
      () async {
        writeProviderConfig('alpha', {'api_key': r'${VENDOR_API_KEY}'});
        final c = AppController(
          loader: UserVoiceConfigLoader(
            configDir: configDir,
            environment: const {},
          ),
          apiKeyStore: await storeLoadedWith('sk-stored'),
        )..setText('A sentence.');

        expect(c.buildConfig().apiKey, 'sk-stored');
        expect(c.apiKeySource, ApiKeySource.keychain);
      },
    );

    test(r'an unresolvable ${ENV} reference does not block the run', () {
      writeProviderConfig('alpha', {'api_key': r'${VENDOR_API_KEY}'});
      final c = makeController()..setText('A sentence.');

      expect(() => c.buildConfig(), returnsNormally);
      expect(c.buildConfig().apiKey, isNull);
      // Not `environment`: nothing was actually sent from the environment.
      expect(c.apiKeySource, ApiKeySource.missing);
    });

    test(
      'a non-alpha provider declaring api_key is recognised as keyed',
      () async {
        writeProviderConfig('groq', {
          'base_url': 'https://api.groq.invalid',
          'api_key': 'gsk-test',
        });
        final c = makeController(apiKeyStore: await storeLoadedWith(null))
          ..setText('A sentence.');

        expect(c.profile?.provider, 'groq');
        expect(c.apiKeySource, ApiKeySource.config);
        expect(c.buildConfig().apiKey, 'gsk-test');
      },
    );

    test(r'a non-alpha provider can use a ${ENV} reference', () {
      writeProviderConfig('groq', {'api_key': r'${GROQ_API_KEY}'});
      final c = makeController(environment: const {'GROQ_API_KEY': 'gsk-env'})
        ..setText('A sentence.');

      expect(c.apiKeySource, ApiKeySource.environment);
      expect(() => c.buildConfig(), returnsNormally);
    });

    test('a keyless provider reports missing but still runs', () async {
      // The local starter: base_url only, no credential.
      writeProviderConfig('beta', {'base_url': 'http://localhost:8000/v1'});
      final c = makeController(apiKeyStore: await storeLoadedWith(null))
        ..setText('A sentence.');

      expect(c.apiKeySource, ApiKeySource.missing);
      final settings = c.buildConfig().providerSettings;
      expect(settings['base_url'], 'http://localhost:8000/v1');
      expect(settings.containsKey('api_key'), isFalse);
    });

    test('a keyless provider still honours a key entered in the app', () async {
      // The point of always offering the section: the config says nothing about
      // a credential, but the user may hold one, and the server — not the app —
      // decides whether it is wanted.
      writeProviderConfig('beta', {'base_url': 'http://localhost:8000/v1'});
      final c = makeController(
        apiKeyStore: await storeLoadedWith('sk-stored', provider: 'beta'),
      )..setText('A sentence.');

      expect(c.apiKeySource, ApiKeySource.keychain);
      expect(c.buildConfig().apiKey, 'sk-stored');
    });

    test('a no-model config reports missing and has no key', () {
      final c = makeController();
      expect(c.activeProvider, isNull);
      expect(c.apiKeySource, ApiKeySource.missing);
    });
  });

  group('model & voice', () {
    test('changeModel resets the voice to the new model default', () {
      writeConfig({
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
            'prompt_style': true,
          },
        },
        'defaults': {'gemini': 'Charon'},
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
        },
      });
      final c = makeController();
      c.changeModel('gemini');
      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'CN2pVME9cDEeMRXJzcMPYj0p');
      expect(c.voiceLabel, 'Charon');
    });

    test('a user-set raw voice survives a model switch', () {
      writeConfig({
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
            'prompt_style': true,
          },
        },
        'defaults': {'gemini': 'Charon'},
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
        },
      });
      final c = makeController();
      c.setVoice('my_custom_voice');
      c.changeModel('gemini');
      expect(c.voice, 'my_custom_voice');
    });

    test('a preserved raw voice drops the previous model label on switch', () {
      writeConfig({
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free', 'format': 'mp3'},
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
            'prompt_style': true,
          },
        },
        'defaults': {'gemini': 'Charon'},
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
          'fish': {'Narrator': 'hex123'},
        },
      });
      final c = makeController();
      c.applyVoiceLabel('Narrator'); // fish alias -> hex123, label Narrator.
      expect(c.voice, 'hex123');
      expect(c.voiceLabel, 'Narrator');
      // gemini's default differs, so the raw voice survives; the fish label
      // must not ride along to a foreign id.
      c.changeModel('gemini');
      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'hex123');
      expect(c.voiceLabel, isNull);
    });

    test('resolveVoice wires a friendly alias to its raw id', () {
      writeConfig({
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free', 'format': 'mp3'},
        },
        'voices': {
          'fish': {'Narrator': 'hex123'},
        },
      });
      final c = makeController();
      c.applyVoiceLabel('Narrator');
      expect(c.voice, 'hex123');
      expect(c.voiceLabel, 'Narrator');
    });
  });

  group('voice gender', () {
    // A provider's `models` list is what claims a model file, so a body
    // naming only one of the two would leave the other orphaned and unread.
    // The combined writer is how a test that needs both declares them.
    final kokoroBody = <String, Object?>{
      'models': {
        'kokoro': {'id': 'hexgrad/kokoro-82m', 'format': 'mp3'},
      },
      'defaults': {'kokoro': 'Emma'},
      'voices': {
        'kokoro': {
          'Alice': {'id': 'bf_alice', 'gender': 'female'},
          'Daniel': {'id': 'bm_daniel', 'gender': 'male'},
          'Emma': {'id': 'bf_emma', 'gender': 'female'},
          'Fable': {'id': 'bm_fable', 'gender': 'male'},
        },
      },
    };

    final geminiBody = <String, Object?>{
      'models': {
        'gemini': {
          'id': 'google/gemini-3.1-flash-tts-preview',
          'format': 'pcm',
          'sample_rate': 24000,
          'prompt_style': true,
        },
      },
      'defaults': {'gemini': 'Charon'},
      'voices': {
        'gemini': {'Charon': 'Charon'},
      },
    };

    void writeKokoro() => writeConfig(kokoroBody);

    void writeGemini() => writeConfig(geminiBody);

    void writeKokoroAndGemini() => writeConfig({
      'models': {
        ...kokoroBody['models']! as Map<String, Object?>,
        ...geminiBody['models']! as Map<String, Object?>,
      },
      'defaults': {
        ...kokoroBody['defaults']! as Map<String, Object?>,
        ...geminiBody['defaults']! as Map<String, Object?>,
      },
      'voices': {
        ...kokoroBody['voices']! as Map<String, Object?>,
        ...geminiBody['voices']! as Map<String, Object?>,
      },
    });

    test('hasGenderTags is true when a model tags voices', () {
      writeKokoro();
      final c = makeController()..changeModel('kokoro');
      expect(c.hasGenderTags, isTrue);
    });

    test('an untagged model has no gender tags', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      expect(c.hasGenderTags, isFalse);
    });

    test('an untagged multilingual model reads its genders off the ids', () {
      writeConfig({
        'models': {
          'kokoro': {
            'id': 'hexgrad/kokoro-82m',
            'format': 'mp3',
            'sends_language': true,
            'default_language': 'b',
            'languages': {'b': 'British English', 'j': 'Japanese'},
          },
        },
        'defaults': {'kokoro': 'bf_emma'},
        'voices': {
          'kokoro': {
            'bf_emma': {'name': 'Emma'},
            'jm_kumo': {'name': 'Kumo'},
          },
        },
      });
      final c = makeController()..changeModel('kokoro');
      expect(c.hasGenderTags, isTrue);
      // The default language narrows the list to the British voice, and its
      // `f` is read straight off the id.
      expect(c.voiceItems.map((e) => e.$2), ['Emma (f)']);
      c.applyVoiceLanguage('j');
      expect(c.voiceItems.map((e) => e.$2), ['Kumo (m)']);
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.voiceItems.map((e) => e.$1), ['Kumo']);
      expect(c.voiceLabel, 'Kumo');
    });

    test('the gender filter narrows voiceItems and appends shorthand', () {
      writeKokoro();
      final c = makeController()..changeModel('kokoro');
      expect(c.voiceItems.map((e) => e.$1), containsAll(['Emma', 'Daniel']));
      c.voiceGenderFilter = VoiceGender.male;
      expect(
        c.voiceItems.map((e) => e.$1),
        unorderedEquals(['Daniel', 'Fable']),
      );
      expect(
        c.voiceItems.map((e) => e.$2),
        containsAll(['Daniel (m)', 'Fable (m)']),
      );
    });

    test('setting a gender filter auto-selects a matching voice', () {
      writeKokoro();
      final c = makeController()..changeModel('kokoro');
      expect(c.voiceLabel, 'Emma'); // default is female
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.voiceLabel, 'Daniel'); // first male entry
      c.voiceGenderFilter = VoiceGender.neutral;
      expect(c.voiceLabel, 'Daniel'); // resetting the filter keeps the pick
    });

    test('changeModel resets the gender filter', () {
      writeKokoroAndGemini();
      final c = makeController()..changeModel('kokoro');
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.voiceGenderFilter, VoiceGender.male);
      c.changeModel('gemini');
      expect(c.voiceGenderFilter, VoiceGender.neutral);
    });

    test('changing gender tweaks the narrator phrase on gemini', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      expect(c.passagePrefix, contains('female narrator'));
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.passagePrefix, contains('male narrator'));
      expect(c.passagePrefix, isNot(contains('female narrator')));
      c.voiceGenderFilter = VoiceGender.female;
      expect(c.passagePrefix, contains('female narrator'));
    });

    test('gender never rewrites a custom prefix without the exact phrase', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      c.passagePrefix = 'Read this in a hushed tone.';
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.passagePrefix, 'Read this in a hushed tone.');
    });

    test('selecting any reverts the narrator phrase on gemini', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      final defaultPrefix = c.passagePrefix;
      expect(defaultPrefix, contains('female narrator'));
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.passagePrefix, contains('male narrator'));
      c.voiceGenderFilter = VoiceGender.neutral;
      expect(c.passagePrefix, defaultPrefix);
    });

    test('male narrator is not mistaken inside a female phrase', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      // The default prefix already says "female narrator"; selecting Female
      // must not treat that phrase's 'male narrator' substring as a male one.
      c.voiceGenderFilter = VoiceGender.female;
      expect(c.passagePrefix, contains('female narrator'));
      expect(c.voiceGenderFilter, VoiceGender.female);
      // Reverting to Any is likewise a no-op on the default phrase.
      c.voiceGenderFilter = VoiceGender.neutral;
      expect(c.passagePrefix, contains('female narrator'));
    });

    test('a gender with no matching voices reverts the filter to any', () {
      writeConfig({
        'models': {
          'single': {'id': 'example/single', 'format': 'mp3'},
        },
        'defaults': {'single': 'Alice'},
        'voices': {
          'single': {
            'Alice': {'id': 'a', 'gender': 'female'},
            'Beth': {'id': 'b', 'gender': 'female'},
          },
        },
      });
      final c = makeController()..changeModel('single');
      expect(c.hasGenderTags, isTrue);
      c.voiceGenderFilter = VoiceGender.male;
      // No male voices: rather than leave a voice hidden behind an empty
      // filter, the pick reverts to "any" and the full list stays available.
      expect(c.voiceGenderFilter, VoiceGender.neutral);
      expect(c.voiceItems.map((e) => e.$1), unorderedEquals(['Alice', 'Beth']));
      expect(c.voiceLabel, 'Alice');
    });

    test('gender on an untagged model leaves the voice list untouched', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      final before = c.voiceItems.map((e) => e.$1).toList();
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.voiceItems.map((e) => e.$1), before);
      expect(c.voiceLabel, 'Charon'); // no auto-switch; default stays
    });
  });

  group('voice language', () {
    final kokoroBody = <String, Object?>{
      'models': {
        'kokoro': {
          'id': 'hexgrad/kokoro-82m',
          'format': 'mp3',
          'sends_language': true,
          'default_language': 'b',
          'languages': {
            'a': 'American English',
            'b': 'British English',
            'j': 'Japanese',
          },
        },
      },
      'defaults': {'kokoro': 'Emma'},
      'voices': {
        'kokoro': {
          'Aria': {'id': 'af_heart', 'gender': 'female'},
          'Alice': {'id': 'bf_alice', 'gender': 'female'},
          'Daniel': {'id': 'bm_daniel', 'gender': 'male'},
          'Emma': {'id': 'bf_emma', 'gender': 'female'},
          'Kumo': {'id': 'jm_kumo', 'gender': 'male'},
        },
      },
    };

    final geminiBody = <String, Object?>{
      'models': {
        'gemini': {
          'id': 'google/gemini-3.1-flash-tts-preview',
          'format': 'pcm',
        },
      },
      'defaults': {'gemini': 'Charon'},
      'voices': {
        'gemini': {'Charon': 'Charon'},
      },
    };

    test('hasLanguages is true when a model declares a language table', () {
      writeConfig(kokoroBody);
      final c = makeController()..changeModel('kokoro');
      expect(c.hasLanguages, isTrue);
      expect(
        c.languageItems.map((e) => e.$1),
        ['a', 'b', 'j'], // declaration order, not sorted
      );
      expect(c.languageItems.map((e) => e.$2), [
        'American English',
        'British English',
        'Japanese',
      ]);
    });

    test('a model with no language table has no languages', () {
      writeConfig(geminiBody);
      final c = makeController()..changeModel('gemini');
      expect(c.hasLanguages, isFalse);
      expect(c.languageItems, isEmpty);
      expect(c.voiceLanguage, isNull);
    });

    test('the language is read off the selected voice id', () {
      writeConfig(kokoroBody);
      final c = makeController()..changeModel('kokoro');
      expect(c.voiceLanguage, 'b'); // bf_emma
      c.setVoice('jm_kumo', label: 'Kumo');
      expect(c.voiceLanguage, 'j');
      // A free-form id outside the table names no language, so the declared
      // default stands in rather than inventing a code.
      c.setVoice('weird_id');
      expect(c.voiceLanguage, 'b');
    });

    test('picking a language narrows the voices and re-picks one', () {
      writeConfig(kokoroBody);
      final c = makeController()..changeModel('kokoro');
      // The model's `default_language` (b) filters the list from the start, so
      // the Japanese Kumo is out of the box.
      expect(c.voiceItems.map((e) => e.$1), ['Alice', 'Daniel', 'Emma']);
      c.applyVoiceLanguage('j');
      expect(c.voiceItems.map((e) => e.$1), ['Kumo']);
      expect(c.voiceLabel, 'Kumo'); // auto-selected to stay visible
      c.applyVoiceLanguage('a');
      expect(c.voiceItems.map((e) => e.$1), ['Aria']);
      expect(c.voiceLabel, 'Aria');
    });

    test('an undeclared language is ignored', () {
      writeConfig(kokoroBody);
      final c = makeController()..changeModel('kokoro');
      c.applyVoiceLanguage('j');
      c.applyVoiceLanguage('z'); // not in the table
      expect(c.voiceLanguage, 'j');
      expect(c.voiceItems.map((e) => e.$1), ['Kumo']);
    });

    test('changing model resets the language to the new default', () {
      writeConfig({
        'models': {
          ...kokoroBody['models']! as Map<String, Object?>,
          'local': {
            'id': 'mlx-community/Kokoro-82M-bf16',
            'format': 'wav',
            'sends_language': true,
            'default_language': 'a',
            'languages': {'a': 'American English', 'b': 'British English'},
          },
        },
        'defaults': {
          ...kokoroBody['defaults']! as Map<String, Object?>,
          'local': 'bf_george',
        },
        'voices': {
          ...kokoroBody['voices']! as Map<String, Object?>,
          'local': {
            'George': {'id': 'bf_george', 'gender': 'male'},
          },
        },
      });
      final c = makeController()..changeModel('kokoro');
      c.applyVoiceLanguage('j');
      expect(c.voiceLanguage, 'j');
      c.changeModel('local');
      expect(c.voiceLanguage, 'a');
      expect(c.languageItems.map((e) => e.$1), ['a', 'b']);
    });
  });

  group('narrate guard', () {
    test('blocks on empty text', () {
      writeFishConfig();
      final c = makeController();
      // An enum, not a rendered sentence: the controller has no BuildContext,
      // so the message is resolved later via `NarrationBlockReasonX.message`.
      expect(c.narrateBlockReason(), NarrationBlockReason.emptyText);
    });

    test('blocks when no model is configured', () {
      final c = makeController();
      expect(c.narrateBlockReason(), NarrationBlockReason.noModelConfigured);
    });

    test('allows narration with text present and a configured model', () {
      writeFishConfig();
      final c = makeController()..setText('Hello world. Enough words.');
      expect(c.narrateBlockReason(), isNull);
    });

    test('blocks re-entrancy once a run starts', () async {
      writeFishConfig();
      final fake = FakeTtsProvider();
      final c = makeController(client: fake.client)
        ..setText('Hello world. Enough words.');
      c.sampleLen = 1;
      c.outDir = dir.path;
      c.startRun();
      expect(c.narrating, isTrue);
      expect(c.narrateBlockReason(), NarrationBlockReason.alreadyRunning);
      // Let the single fake segment land.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.narrating, isFalse);
      expect(c.narrateBlockReason(), isNull);
      expect(fake.callCount, 1);
    });

    test('command slots start unwired', () {
      final c = makeController();
      expect(c.commands.onOpen, isNull);
      expect(c.commands.onNarrate, isNull);
      expect(c.commands.onCancel, isNull);
      expect(c.commands.onPreferences, isNull);
    });
  });

  group('run state', () {
    // Every run test narrates a configured model; without one, startRun() is
    // blocked by the no-model guard before the first segment is planned.
    setUp(() => writeFishConfig());

    test('sampleLen sizes the segment plan so progress completes at 100%', () async {
      final fake = FakeTtsProvider();
      final c = makeController(client: fake.client);
      c.setText(
        'First paragraph with enough words to become its own segment and then '
        'carry on a little longer to cross the minimum.\n\n'
        'Second paragraph with enough words to become its own segment as well '
        'and then carry on a little longer to cross the minimum.',
      );
      c.sampleLen = 1;
      c.outDir = dir.path;
      c.startRun();
      expect(c.totalSegments, 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.runDoneCount, 1);
      expect(c.runProgress, 1.0);
      expect(fake.callCount, 1);
    });

    test('cancelling a run clears the in-flight segment spinner', () async {
      final fake = FakeTtsProvider();
      final c = makeController(client: fake.client);
      c.setText(
        'First paragraph with enough words to become its own segment and then '
        'carry on a little longer to cross the minimum.\n\n'
        'Second paragraph with enough words to become its own segment as well '
        'and then carry on a little longer to cross the minimum.',
      );
      c.outDir = dir.path;
      c.startRun();
      c.cancelRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runStopped, isTrue);
      expect(c.narrating, isFalse);
      expect(c.runSegments.every((segment) => !segment.running), isTrue);
    });

    test('a successful run records the combined track path', () async {
      final fake = FakeTtsProvider();
      final c = makeController(client: fake.client);
      c.setText(
        'A single paragraph long enough that it does not need any other '
        'company. It crosses the minimum word count comfortably and becomes '
        'one segment all on its own, plain and simple.',
      );
      c.outDir = dir.path;
      expect(c.completedAudioPath, isNull);
      c.startRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      final path = c.completedAudioPath;
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      expect(path, endsWith('untitled_full.mp3'));
    });

    test('a cancelled run never records a combined track path', () async {
      final fake = FakeTtsProvider();
      final c = makeController(client: fake.client);
      c.setText(
        'First paragraph with enough words to become its own segment and then '
        'carry on a little longer to cross the minimum.\n\n'
        'Second paragraph with enough words to become its own segment as well '
        'and then carry on a little longer to cross the minimum.',
      );
      c.outDir = dir.path;
      c.startRun();
      c.cancelRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runStopped, isTrue);
      expect(c.completedAudioPath, isNull);
    });

    test('cancelRun makes narration idle immediately', () async {
      final fake = FakeTtsProvider();
      final c = makeController(client: fake.client);
      c.setText(
        'First paragraph with enough words to become its own segment and then '
        'carry on a little longer to cross the minimum.\n\n'
        'Second paragraph with enough words to become its own segment as well '
        'and then carry on a little longer to cross the minimum.',
      );
      final gate = Completer<void>();
      fake.gate = gate;
      c.outDir = dir.path;
      c.startRun();
      expect(c.narrating, isTrue);
      // Cancel must release the controller immediately: a new run can start
      // while the cancelled request is still unwinding, with no "already
      // running" guard left over.
      c.cancelRun();
      expect(c.narrating, isFalse);
      expect(c.narrateBlockReason(), isNull);
      // Let the abandoned request settle and confirm the controller stays idle.
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.narrating, isFalse);
      expect(c.narrateBlockReason(), isNull);
      expect(c.runStopped, isTrue);
    });

    test('a successor run is not clobbered by the cancelled predecessor', () async {
      final fake = FakeTtsProvider();
      final c = makeController(client: fake.client);
      c.setText(
        'First paragraph with enough words to become its own segment on its '
        'own, carrying straight past the minimum without needing any company '
        'from a neighbouring paragraph. It simply keeps going until it clears '
        'the bar here.\n\n'
        'Second paragraph with enough words to become its own segment as well, '
        'also carrying well past the minimum so it does not fuse with anything '
        'around it either. It clears the bar all by itself just the same.',
      );
      final gate = Completer<void>();
      fake.gate = gate;
      c.outDir = dir.path;
      c.sampleLen = null;
      // Run A: gated mid-flight, then cancelled.
      c.startRun();
      c.cancelRun();
      // Run B: starts while A's request is still in flight (gate not yet
      // released), and must finish cleanly.
      c.startRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.narrating, isFalse);
      // Release A's stale request; its unwind must not mark B stopped, blank
      // its progress, or drop its combined track.
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.runStopped, isFalse);
      expect(c.narrating, isFalse);
      expect(c.runDoneCount, 2);
      expect(c.runError, isNull);
      expect(c.completedAudioPath, isNotNull);
    });

    test('starting a new run clears a prior completed track path', () async {
      final fake = FakeTtsProvider();
      final c = makeController(client: fake.client);
      c.setText(
        'A single paragraph long enough that it does not need any other '
        'company. It crosses the minimum word count comfortably and becomes '
        'one segment all on its own, plain and simple.',
      );
      c.outDir = dir.path;
      c.startRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.completedAudioPath, isNotNull);

      // A second run resets the path while it generates, then restores it on
      // completion.
      c.setText(
        'A different single paragraph long enough to stand alone too. It '
        'easily crosses the minimum word count and becomes its own segment, '
        'just like the first one did before it.',
      );
      c.startRun();
      expect(c.completedAudioPath, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.completedAudioPath, isNotNull);
    });

    test('canCleanupSegments enables and cleanupSegments removes per-segment '
        'files while keeping the combined track', () async {
      final fake = FakeTtsProvider();
      final c = makeController(client: fake.client);
      c.setText(
        'A single paragraph long enough that it does not need any other '
        'company. It crosses the minimum word count comfortably and becomes '
        'one segment all on its own, plain and simple.',
      );
      c.outDir = dir.path;
      c.startRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.narrating, isFalse);

      expect(c.canCleanupSegments, isTrue);

      final outDir = Directory('${dir.path}/untitled');
      expect(File('${outDir.path}/untitled_full.mp3').existsSync(), isTrue);
      final manifestPath = '${outDir.path}/manifest.json';
      expect(File(manifestPath).existsSync(), isTrue);

      final removed = await c.cleanupSegments();

      expect(removed, 1); // one paragraph -> one segment file.
      expect(
        outDir.listSync().whereType<File>().length,
        2,
      ); // combined + manifest
      expect(c.canCleanupSegments, isFalse);
      // Tiles no longer point at deleted files.
      expect(c.runSegments.single.filePath, isNull);
      final manifest = jsonDecode(
        File(manifestPath).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(manifest['segments_deleted'], isTrue);
      expect(fake.callCount, 1);
    });

    test('cleanupSegments before any run is a harmless no-op', () async {
      final c = makeController();
      expect(c.canCleanupSegments, isFalse);
      expect(await c.cleanupSegments(), 0);
    });

    test('cleanupSegments is a no-op while a run is in flight', () async {
      final fake = FakeTtsProvider();
      final c = makeController(client: fake.client)
        ..setText('Hello world. Enough words.');
      c.sampleLen = 1;
      c.outDir = dir.path;
      c.startRun();
      expect(c.narrating, isTrue);
      expect(await c.cleanupSegments(), 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });

  group('modelUiSpec', () {
    test('empty when the active model declares no capabilities', () {
      final c = makeController();
      expect(c.modelUiSpec.isEmpty, isTrue);
    });

    test('prompt_style derives the prompt controls for the active model', () {
      writePromptStyleFishConfig();
      final c = makeController();
      expect(c.modelUiSpec.isEmpty, isFalse);
      final keys = c.modelUiSpec.options.map((o) => o.key).toList();
      expect(keys, ['gender', 'accent', 'style', 'passagePrefix']);
    });

    test('speed adds only the speed control', () {
      writeConfig({
        'providers': {
          'alpha': {
            'base_url': 'https://vendor.example/api/v1',
            'api_key': 'sk-test',
          },
        },
        'models': {
          'fast': {
            'id': 'openai/gpt-4o-mini-tts',
            'format': 'mp3',
            'speed': true,
          },
        },
      });
      final c = makeController();
      final keys = c.modelUiSpec.options.map((o) => o.key).toList();
      expect(keys, ['speed']);
    });

    test('follows the selected model when it switches', () {
      writeConfig({
        'providers': {
          'alpha': {
            'base_url': 'https://vendor.example/api/v1',
            'api_key': 'sk-test',
          },
        },
        'models': {
          'plain': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
          'styled': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
            'prompt_style': true,
          },
        },
      });
      final c = makeController();
      expect(c.modelUiSpec.isEmpty, isTrue);
      c.changeModel('styled');
      final keys = c.modelUiSpec.options.map((o) => o.key).toList();
      expect(keys, ['gender', 'accent', 'style', 'passagePrefix']);
    });
  });

  group('estimate', () {
    test('plans and estimates update with the text', () {
      writeFishConfig();
      final c = makeController();
      c.setText(
        'The rain fell on the quiet street. Lights glowed behind the windows. '
        'It was an evening of small, patient sounds. The story drifted on for '
        'a while, unhurried and calm.',
      );
      final segments = c.plannedSegments;
      expect(segments, isNotEmpty);
      expect(c.estimatedMinutes, greaterThan(0));
      expect(c.estimatedCostUsd, 0); // fish is free.
    });
  });

  group('appearance', () {
    test('defaults to following the system appearance', () {
      final c = makeController();
      expect(c.themeMode, AppThemeMode.system);
    });

    test('themeMode write updates the value and notifies listeners', () {
      final c = makeController();
      var notifications = 0;
      c.addListener(() => notifications++);

      c.themeMode = AppThemeMode.dark;
      expect(c.themeMode, AppThemeMode.dark);
      expect(notifications, 1);

      c.themeMode = AppThemeMode.light;
      expect(c.themeMode, AppThemeMode.light);
      expect(notifications, 2);
    });

    test('identical themeMode write is ignored', () {
      final c = makeController();
      var notifications = 0;
      c.addListener(() => notifications++);
      c.themeMode = AppThemeMode.system;
      expect(notifications, 0);
    });
  });

  group('settings panel', () {
    test('starts visible', () {
      final c = makeController();
      expect(c.settingsPanelVisible, isTrue);
    });

    test('toggleSettingsPanel flips the value and notifies listeners', () {
      final c = makeController();
      var notifications = 0;
      c.addListener(() => notifications++);

      c.toggleSettingsPanel();
      expect(c.settingsPanelVisible, isFalse);
      expect(notifications, 1);

      c.toggleSettingsPanel();
      expect(c.settingsPanelVisible, isTrue);
      expect(notifications, 2);
    });
  });

  group('settings setters', () {
    test('every setting write notifies listeners once', () {
      final c = makeController();
      var notifications = 0;
      c.addListener(() => notifications++);

      c.accent = 'x';
      c.style = 'y';
      c.passagePrefix = 'z';
      c.minWords = 10;
      c.sampleLen = 2;
      c.outDir = 'out';
      c.resume = true;

      expect(c.accent, 'x');
      expect(c.style, 'y');
      expect(c.passagePrefix, 'z');
      expect(c.minWords, 10);
      expect(c.sampleLen, 2);
      expect(c.outDir, 'out');
      expect(c.resume, isTrue);
      expect(notifications, 7);
    });

    test('identical setting writes are ignored', () {
      final c = makeController();
      var notifications = 0;
      c.addListener(() => notifications++);

      c.resume = false; // already the default
      c.accent = c.accent; // already set

      expect(notifications, 0);
    });

    test('min words clamps to the settings slider range (10-100)', () {
      final c = makeController();
      c.minWords = 0;
      expect(c.minWords, 10);
      c.minWords = -5;
      expect(c.minWords, 10);
      c.minWords = 1000;
      expect(c.minWords, 100);
    });

    test('sample length can be cleared back to null', () {
      final c = makeController();
      c.sampleLen = 4;
      expect(c.sampleLen, 4);
      c.sampleLen = null;
      expect(c.sampleLen, isNull);
    });
  });

  group('output folder persistence', () {
    test('loads a previously saved output folder on construction', () async {
      SharedPreferences.setMockInitialValues({'outDir': '/tmp/saved'});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController(
        loader: UserVoiceConfigLoader(configDir: configDir),
        prefs: prefs,
      );
      expect(c.outDir, '/tmp/saved');
    });

    test('persists an output folder change to the preference store', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController(
        loader: UserVoiceConfigLoader(configDir: configDir),
        prefs: prefs,
      );
      c.outDir = '/tmp/picked';
      expect(prefs.getString('outDir'), '/tmp/picked');
    });

    test('falls back to the default when no folder is saved', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController(
        loader: UserVoiceConfigLoader(configDir: configDir),
        prefs: prefs,
      );
      // Absolute and under the system temp dir: playback on Linux runs
      // through GStreamer, which cannot resolve a path relative to the
      // working directory a packaged app happens to inherit.
      expect(c.outDir, SettingsController.defaultOutDir());
      expect(c.outDir, startsWith(Directory.systemTemp.path));
      expect(Directory(c.outDir).existsSync(), isTrue);
    });

    test('falls back to the default when the saved value is empty', () async {
      SharedPreferences.setMockInitialValues({'outDir': ''});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController(
        loader: UserVoiceConfigLoader(configDir: configDir),
        prefs: prefs,
      );
      expect(c.outDir, SettingsController.defaultOutDir());
      expect(c.outDir, startsWith(Directory.systemTemp.path));
    });
  });
}
