import 'dart:async';
import 'dart:io';

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

    test(
      'cancelling while a request is in flight aborts the live HTTP call',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requestArrived = Completer<void>();
        final serverDone = server.listen((request) {
          // Never respond: hold the connection open until the client aborts.
          requestArrived.complete();
        });
        final token = AbortToken();
        final provider = OpenRouterTtsProvider(
          environment: const {},
          endpoint: 'http://${server.address.address}:${server.port}',
        );
        final future = provider.synthesize(
          model: 'test/model',
          voice: null,
          responseFormat: 'mp3',
          input: 'hello',
          settings: const {'api_key': 'sk-test'},
          abort: token,
        );
        await requestArrived.future;
        token.cancel();
        await expectLater(future, throwsA(isA<AbortException>()));
        await serverDone.cancel();
        await server.close(force: true);
      },
    );
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
            allOf(contains('api_key'), contains('OPENROUTER_API_KEY')),
          ),
        ),
      );
    });
  });

  group('modelUiSpecFor', () {
    test('a prompt-styled model declares its styling options', () {
      const styled = TtsModelProfile(
        alias: 'gemini',
        id: 'google/gemini-3.1-flash-tts-preview',
        promptStyle: true,
      );
      final spec = OpenRouterTtsProvider().modelUiSpecFor(styled);
      expect(spec.isEmpty, isFalse);
      expect(spec.options.map((o) => o.key), [
        'gender',
        'accent',
        'style',
        'passagePrefix',
        'useCalmTag',
      ]);
      expect(
        spec.options.firstWhere((o) => o.key == 'gender').type,
        ModelUiOptionType.gender,
      );
      expect(
        spec.options.firstWhere((o) => o.key == 'passagePrefix').type,
        ModelUiOptionType.multiline,
      );
      expect(
        spec.options.firstWhere((o) => o.key == 'useCalmTag').type,
        ModelUiOptionType.bool,
      );
    });

    test('a prompt-styled model with a renamed alias still declares them', () {
      // A user may alias the gemini model to anything; the UI is keyed off the
      // request-shape promptStyle flag, not the user-editable alias.
      const renamed = TtsModelProfile(
        alias: 'my-gemini',
        id: 'google/gemini-3.1-flash-tts-preview',
        promptStyle: true,
      );
      final spec = OpenRouterTtsProvider().modelUiSpecFor(renamed);
      expect(spec.isEmpty, isFalse);
      expect(spec.options, hasLength(5));
    });

    test('models without prompt styling declare nothing', () {
      final provider = OpenRouterTtsProvider();
      const fish = TtsModelProfile(
        alias: 'fish',
        id: 'fish-audio/s2.1-pro-free',
      );
      const kokoro = TtsModelProfile(alias: 'kokoro', id: 'hexgrad/kokoro-82m');
      expect(provider.modelUiSpecFor(fish).isEmpty, isTrue);
      expect(provider.modelUiSpecFor(kokoro).isEmpty, isTrue);
    });
  });
}
