import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/api_key_store.dart';

void main() {
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
      expect(store.value, isNull);
    });

    test(
      'load pulls a stored value and trims surrounding whitespace',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          'openrouter_api_key': '  sk-from-keychain  ',
        });
        final store = await loadedStore();
        expect(store.value, 'sk-from-keychain');
      },
    );

    test('load never notifies when the cached value is unchanged', () async {
      FlutterSecureStorage.setMockInitialValues({
        'openrouter_api_key': 'sk-test',
      });
      final store = await loadedStore();
      var notified = 0;
      store.addListener(() => notified++);
      await store.load(); // same value -> no notification.
      expect(notified, 0);
    });

    test('load treats a blank stored value as "no key"', () async {
      FlutterSecureStorage.setMockInitialValues({'openrouter_api_key': '   '});
      final store = await loadedStore();
      expect(store.value, isNull);
    });

    test('save trims the key, caches it, notifies, and persists', () async {
      final store = ApiKeyStore();
      var notified = 0;
      store.addListener(() => notified++);
      await store.save('  sk-persisted  ');
      expect(store.value, 'sk-persisted');
      expect(notified, 1);
      // A fresh store on the same backend sees the written value.
      final reloaded = await loadedStore();
      expect(reloaded.value, 'sk-persisted');
    });

    test(
      'save rejects an empty/whitespace key without touching the cache',
      () async {
        final store = ApiKeyStore();
        await expectLater(() => store.save('   '), throwsArgumentError);
        expect(store.value, isNull);
      },
    );

    test('remove clears the cached and persisted value and notifies', () async {
      FlutterSecureStorage.setMockInitialValues({
        'openrouter_api_key': 'sk-test',
      });
      final store = await loadedStore();
      var notified = 0;
      store.addListener(() => notified++);
      await store.remove();
      expect(store.value, isNull);
      expect(notified, 1);
      expect((await loadedStore()).value, isNull);
    });

    test('a failed read is treated as "no stored key"', () async {
      // The default method-channel backend has no binding in a pure Dart test,
      // so `read` throws; load() must swallow it and stay null, not fail.
      final store = ApiKeyStore(); // uses the default (channel) backend.
      await expectLater(store.load(), completes);
      expect(store.value, isNull);
    });
  });
}
