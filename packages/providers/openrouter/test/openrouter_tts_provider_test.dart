import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'package:tts_narrator_openrouter/openrouter_tts_provider.dart';

void main() {
  group('AbortToken in OpenRouterTtsProvider', () {
    test('an already-cancelled token aborts before any network call', () {
      final provider = OpenRouterTtsProvider(environment: const {});
      final token = AbortToken()..cancel();
      expect(
        () => provider.synthesize(
          model: 'test/model',
          voice: null,
          responseFormat: 'mp3',
          input: 'hello',
          settings: const {'api_key': 'sk-test'},
          abort: token,
        ),
        throwsA(isA<AbortException>()),
      );
    });
  });

  group('API key resolution', () {
    test('throws naming the missing source when no key is set any way', () async {
      final provider = OpenRouterTtsProvider(environment: const {});
      // No key in settings or the (injected, empty) environment — the provider
      // must throw before any HTTP call, naming what's missing.
      await expectLater(
        provider.synthesize(
          model: 'test/model',
          voice: null,
          responseFormat: 'mp3',
          input: 'hello',
          settings: const {},
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('api_key'),
              contains('OPENROUTER_API_KEY'),
            ),
          ),
        ),
      );
    });
  });
}