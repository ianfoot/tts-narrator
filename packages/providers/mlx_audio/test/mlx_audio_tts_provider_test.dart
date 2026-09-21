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
    test('posts the Kokoro model, default voice, mp3 format and speed to the '
        'local endpoint', () async {
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
        model: 'irrelevant',
        voice: null,
        responseFormat: 'irrelevant',
        input: 'The quick brown fox.',
        settings: const {},
      );
      expect(utf8.decode(audio.bytes), 'fake-audio-bytes');

      final decoded = jsonDecode(await received.future) as Map;
      expect(decoded['model'], 'mlx-community/Kokoro-82M-bf16');
      expect(decoded['voice'], 'bm_george');
      expect(decoded['response_format'], 'mp3');
      expect(decoded['speed'], 0.8);
      expect(decoded['input'], 'The quick brown fox.');

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
  });

  group('modelUiSpecFor', () {
    test('declares no options for any model', () {
      final provider = MlxAudioTtsProvider();
      const kokoro = TtsModelProfile(
        alias: 'kokoro',
        id: 'mlx-community/Kokoro-82M-bf16',
      );
      expect(provider.modelUiSpecFor(kokoro).isEmpty, isTrue);
    });

    test('reports id and name', () {
      final provider = MlxAudioTtsProvider();
      expect(provider.id, 'mlx_audio');
      expect(provider.name, 'MLX Audio');
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
