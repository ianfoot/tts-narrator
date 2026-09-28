import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'package:tts_narrator_mlx_audio/mlx_audio_tts_provider.dart';

void main() {
  group('AbortToken in MlxAudioTtsProvider', () {
    test('an already-cancelled token aborts before any network call', () {
      final provider = MlxAudioTtsProvider();
      final token = AbortToken()..cancel();
      expect(
        () => provider.synthesize(
          model: 'mlx-community/Kokoro-82M-bf16',
          voice: null,
          responseFormat: 'mp3',
          input: 'hello',
          settings: const {},
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
        final provider = MlxAudioTtsProvider(
          endpoint: 'http://${server.address.address}:${server.port}',
        );
        final future = provider.synthesize(
          model: 'mlx-community/Kokoro-82M-bf16',
          voice: null,
          responseFormat: 'mp3',
          input: 'hello',
          settings: const {},
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

  group('synthesize request shape', () {
    test('posts the requested model, default voice, requested format and speed '
        'to the local endpoint', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<String>();
      final serverDone = server.listen((request) async {
        final body = await _readBody(request);
        received.complete(body);
        request.response.write('fake-audio-bytes');
        await request.response.close();
      });
      final provider = MlxAudioTtsProvider(
        endpoint: 'http://${server.address.address}:${server.port}',
      );
      final audio = await provider.synthesize(
        model: 'some/other-model',
        voice: null,
        responseFormat: 'wav',
        input: 'The quick brown fox.',
        settings: const {},
        speed: 0.8,
      );
      expect(utf8.decode(audio.bytes), 'fake-audio-bytes');

      final decoded = jsonDecode(await received.future) as Map;
      expect(decoded['model'], 'some/other-model');
      expect(decoded['voice'], 'bm_george');
      expect(decoded['response_format'], 'wav');
      expect(decoded['speed'], 0.8);
      expect(decoded['input'], 'The quick brown fox.');

      await serverDone.cancel();
      await server.close(force: true);
    });

    test('falls back to the Kokoro model when the profile model is empty',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<String>();
      final serverDone = server.listen((request) async {
        final body = await _readBody(request);
        received.complete(body);
        request.response.write('x');
        await request.response.close();
      });
      final provider = MlxAudioTtsProvider(
        endpoint: 'http://${server.address.address}:${server.port}',
      );
      await provider.synthesize(
        model: '  ',
        voice: null,
        responseFormat: 'wav',
        input: 'Hi',
        settings: const {},
      );
      final decoded = jsonDecode(await received.future) as Map;
      expect(decoded['model'], 'mlx-community/Kokoro-82M-bf16');
      await serverDone.cancel();
      await server.close(force: true);
    });

    test('honours an explicit voice over the default', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<String>();
      final serverDone = server.listen((request) async {
        final body = await _readBody(request);
        received.complete(body);
        request.response.write('x');
        await request.response.close();
      });
      final provider = MlxAudioTtsProvider(
        endpoint: 'http://${server.address.address}:${server.port}',
      );
      await provider.synthesize(
        model: 'irrelevant',
        voice: 'bf_emma',
        responseFormat: 'irrelevant',
        input: 'Hi',
        settings: const {},
      );
      final decoded = jsonDecode(await received.future) as Map;
      expect(decoded['voice'], 'bf_emma');
      await serverDone.cancel();
      await server.close(force: true);
    });

    test('uses the endpoint from provider settings over the constructor value',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final served = Completer<String?>();
      final serverDone = server.listen((request) async {
        served.complete(request.headers.value(HttpHeaders.authorizationHeader));
        request.response.write('x');
        await request.response.close();
      });
      final provider = MlxAudioTtsProvider(
        endpoint: 'http://unreachable.invalid', // superseded by settings
      );
      await provider.synthesize(
        model: 'mlx-community/Kokoro-82M-bf16',
        voice: null,
        responseFormat: 'wav',
        input: 'Hi',
        settings: {
          'endpoint': 'http://${server.address.address}:${server.port}',
        },
      );
      // The request reached the settings-provided server, and carried no auth.
      expect(await served.future, isNull);
      await serverDone.cancel();
      await server.close(force: true);
    });

    test('sends a Bearer token only when an api_key setting exists',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final served = Completer<String>();
      final serverDone = server.listen((request) async {
        served.complete(request.headers.value(HttpHeaders.authorizationHeader));
        request.response.write('x');
        await request.response.close();
      });
      final provider = MlxAudioTtsProvider(
        endpoint: 'http://${server.address.address}:${server.port}',
      );
      // With an api_key setting the header is present.
      await provider.synthesize(
        model: 'mlx-community/Kokoro-82M-bf16',
        voice: null,
        responseFormat: 'wav',
        input: 'Hi',
        settings: {'api_key': 'secret'},
      );
      expect(await served.future, 'Bearer secret');
      await serverDone.cancel();
      await server.close(force: true);
    });

    test('omits the auth header when no api_key setting exists', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final served = Completer<String?>();
      final serverDone = server.listen((request) async {
        served.complete(request.headers.value(HttpHeaders.authorizationHeader));
        request.response.write('x');
        await request.response.close();
      });
      final provider = MlxAudioTtsProvider(
        endpoint: 'http://${server.address.address}:${server.port}',
      );
      await provider.synthesize(
        model: 'mlx-community/Kokoro-82M-bf16',
        voice: null,
        responseFormat: 'wav',
        input: 'Hi',
        settings: const {},
      );
      expect(await served.future, isNull);
      await serverDone.cancel();
      await server.close(force: true);
    });
  });

  group('modelUiSpecFor', () {
    test('declares a speed control for kokoro-family models', () {
      final provider = MlxAudioTtsProvider();
      const kokoro = TtsModelProfile(
        alias: 'kokoro',
        id: 'mlx-community/Kokoro-82M-bf16',
      );
      final spec = provider.modelUiSpecFor(kokoro);
      expect(spec.isEmpty, isFalse);
      expect(spec.options.map((o) => o.key), contains('speed'));
      expect(
        spec.options.map((o) => o.type),
        contains(ModelUiOptionType.speed),
      );
    });

    test('declares nothing for non-kokoro models', () {
      final provider = MlxAudioTtsProvider();
      const other = TtsModelProfile(alias: 'other', id: 'some/model');
      expect(provider.modelUiSpecFor(other).isEmpty, isTrue);
    });

    test('reports id and name', () {
      final provider = MlxAudioTtsProvider();
      expect(provider.id, 'mlx_audio');
      expect(provider.name, 'Local OpenAI-compatible');
    });
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
