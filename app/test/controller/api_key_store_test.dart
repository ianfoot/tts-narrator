import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/api_key_store.dart';

void main() {
  /// The provider most tests exercise. Arbitrary — the store must not know or
  /// care which vendor it is; that is the point of the per-provider key.
  const provider = 'alpha';

  setUp(() {
    // A mutable map: the in-memory "keychain" also has to accept writes.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  /// Loads the store once against the current mock values, mirroring the app's
  /// startup load.
  Future<ApiKeyStore> loadedStore() async {
    final store = ApiKeyStore();
    await store.load();
    return store;
  }

  group('ApiKeyStore', () {
    test('value is null when nothing is stored', () async {
      final store = await loadedStore();
      expect(store.value(provider), isNull);
    });

    test(
      'load pulls a stored value and trims surrounding whitespace',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          'tts-narrator.api_key.$provider': '  sk-from-keychain  ',
        });
        final store = await loadedStore();
        expect(store.value(provider), 'sk-from-keychain');
      },
    );

    test('load never notifies when the cached value is unchanged', () async {
      FlutterSecureStorage.setMockInitialValues({
        'tts-narrator.api_key.$provider': 'sk-test',
      });
      final store = await loadedStore();
      var notified = 0;
      store.addListener(() => notified++);
      await store.load(); // same value -> no notification.
      expect(notified, 0);
    });

    test('load treats a blank stored value as "no key"', () async {
      FlutterSecureStorage.setMockInitialValues({
        'tts-narrator.api_key.$provider': '   ',
      });
      final store = await loadedStore();
      expect(store.value(provider), isNull);
    });

    test('save trims the key, caches it, notifies, and persists', () async {
      final store = ApiKeyStore();
      var notified = 0;
      store.addListener(() => notified++);
      await store.save(provider, '  sk-persisted  ');
      expect(store.value(provider), 'sk-persisted');
      expect(notified, 1);
      // A fresh store on the same backend sees the written value.
      final reloaded = await loadedStore();
      expect(reloaded.value(provider), 'sk-persisted');
    });

    test(
      'save rejects an empty/whitespace key without touching the cache',
      () async {
        final store = ApiKeyStore();
        await expectLater(
          () => store.save(provider, '   '),
          throwsArgumentError,
        );
        expect(store.value(provider), isNull);
      },
    );

    test('remove clears the cached and persisted value and notifies', () async {
      FlutterSecureStorage.setMockInitialValues({
        'tts-narrator.api_key.$provider': 'sk-test',
      });
      final store = await loadedStore();
      var notified = 0;
      store.addListener(() => notified++);
      await store.remove(provider);
      expect(store.value(provider), isNull);
      expect(notified, 1);
      expect((await loadedStore()).value(provider), isNull);
    });

    test('a failed read is treated as "no stored key"', () async {
      // The default method-channel backend has no binding in a pure Dart test,
      // so `readAll` throws; load() must swallow it and stay empty, not fail.
      final store = ApiKeyStore(); // uses the default (channel) backend.
      await expectLater(store.load(), completes);
      expect(store.value(provider), isNull);
    });

    group('per provider', () {
      test('two providers hold independent keys', () async {
        FlutterSecureStorage.setMockInitialValues({
          'tts-narrator.api_key.alpha': 'sk-test',
          'tts-narrator.api_key.groq': 'gsk-groq',
        });
        final store = await loadedStore();
        expect(store.value('alpha'), 'sk-test');
        expect(store.value('groq'), 'gsk-groq');
      });

      test('an unknown provider reads as no key', () async {
        FlutterSecureStorage.setMockInitialValues({
          'tts-narrator.api_key.alpha': 'sk-test',
        });
        final store = await loadedStore();
        expect(store.value('groq'), isNull);
      });

      test('entries outside the namespace are ignored', () async {
        // The platform backends hand back every entry belonging to the app, so
        // the prefix filter is what keeps an unrelated value out of the cache.
        FlutterSecureStorage.setMockInitialValues({
          'tts-narrator.api_key.alpha': 'sk-test',
          'some.other.setting': 'not-a-key',
          'tts-narrator.api_key.': 'no-provider-segment',
        });
        final store = await loadedStore();
        expect(store.value(provider), 'sk-test');
        expect(store.value(''), isNull);
        expect(store.value('some.other.setting'), isNull);
      });

      test('save for one provider leaves the other alone', () async {
        FlutterSecureStorage.setMockInitialValues({
          'tts-narrator.api_key.alpha': 'sk-test',
        });
        final store = await loadedStore();
        await store.save('groq', 'gsk-groq');
        expect(store.value('groq'), 'gsk-groq');
        expect(store.value('alpha'), 'sk-test');
      });

      test('remove takes only the named provider with it', () async {
        FlutterSecureStorage.setMockInitialValues({
          'tts-narrator.api_key.alpha': 'sk-test',
          'tts-narrator.api_key.groq': 'gsk-groq',
        });
        final store = await loadedStore();
        await store.remove('groq');
        expect(store.value('groq'), isNull);
        expect(store.value('alpha'), 'sk-test');
      });
    });
  });
}
