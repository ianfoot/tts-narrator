import 'dart:async';
import 'dart:convert';
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
      ]);
      expect(
        spec.options.firstWhere((o) => o.key == 'gender').type,
        ModelUiOptionType.gender,
      );
      expect(
        spec.options.firstWhere((o) => o.key == 'passagePrefix').type,
        ModelUiOptionType.multiline,
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
      expect(spec.options, hasLength(4));
    });

    test('the kokoro-family model declares a speed control', () {
      final provider = OpenRouterTtsProvider();
      const kokoro = TtsModelProfile(alias: 'kokoro', id: 'hexgrad/kokoro-82m');
      final spec = provider.modelUiSpecFor(kokoro);
      expect(spec.isEmpty, isFalse);
      expect(spec.options.map((o) => o.key), ['speed']);
      expect(
        spec.options.firstWhere((o) => o.key == 'speed').type,
        ModelUiOptionType.speed,
      );
      // A prompt-styled model keeps its styling options and gains no speed
      // control (only kokoro-family ids declare one).
      const styled = TtsModelProfile(
        alias: 'gemini',
        id: 'google/gemini-3.1-flash-tts-preview',
        promptStyle: true,
      );
      final styledSpec = provider.modelUiSpecFor(styled);
      expect(
        styledSpec.options.map((o) => o.key),
        ['gender', 'accent', 'style', 'passagePrefix'],
      );
      expect(styledSpec.options.map((o) => o.key), isNot(contains('speed')));
    });

    test('models without prompt styling or a kokoro id declare nothing', () {
      final provider = OpenRouterTtsProvider();
      const fish = TtsModelProfile(
        alias: 'fish',
        id: 'fish-audio/s2.1-pro-free',
      );
      expect(provider.modelUiSpecFor(fish).isEmpty, isTrue);
    });
  });

  group('synthesize speed', () {
    test('a non-default speed is posted in the request body', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<Map>();
      final serverDone = server.listen((request) async {
        received.complete(jsonDecode(await _readBody(request)) as Map);
        request.response.write('fake-audio-bytes');
        await request.response.close();
      });
      final provider = OpenRouterTtsProvider(
        environment: const {},
        endpoint: 'http://${server.address.address}:${server.port}',
      );
      final audio = await provider.synthesize(
        model: 'hexgrad/kokoro-82m',
        voice: 'bf_emma',
        responseFormat: 'mp3',
        input: 'The quick brown fox.',
        settings: const {'api_key': 'sk-test'},
        speed: 0.75,
      );
      expect(utf8.decode(audio.bytes), 'fake-audio-bytes');
      final decoded = await received.future;
      expect(decoded['speed'], 0.75);
      await serverDone.cancel();
      await server.close(force: true);
    });

    test(
      'default speed (1.0) is omitted so existing requests are unchanged',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final received = Completer<Map>();
        final serverDone = server.listen((request) async {
          received.complete(jsonDecode(await _readBody(request)) as Map);
          request.response.write('x');
          await request.response.close();
        });
        final provider = OpenRouterTtsProvider(
          environment: const {},
          endpoint: 'http://${server.address.address}:${server.port}',
        );
        await provider.synthesize(
          model: 'google/gemini-3.1-flash-tts-preview',
          voice: null,
          responseFormat: 'mp3',
          input: 'Hi',
          settings: const {'api_key': 'sk-test'},
        );
        final decoded = await received.future;
        expect(decoded.containsKey('speed'), isFalse);
        await serverDone.cancel();
        await server.close(force: true);
      },
    );
  });
}

/// Folds the request body into a decoded string.
Future<String> _readBody(HttpRequest request) async {
  final bytes = await request.fold<List<int>>(
    <int>[],
    (acc, segment) => acc..addAll(segment),
  );
  return utf8.decode(bytes);
}
