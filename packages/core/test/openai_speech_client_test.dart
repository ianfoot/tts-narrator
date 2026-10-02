import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

/// A loopback `/audio/speech` server that records what it received.
class _Server {
  _Server(this._server)
    : root = 'http://${_server.address.host}:${_server.port}';

  final HttpServer _server;
  final String root;

  /// Completes when the first request arrives.
  final arrived = Completer<void>();

  final requests = <_Request>[];

  /// A ready-to-pass provider block pointing at this server.
  Map<String, String> get block => {'base_url': root};

  Future<void> close() => _server.close(force: true);
}

/// One request as the server saw it.
class _Request {
  _Request(this.uri, this.headers, this.body);

  final Uri uri;
  final HttpHeaders headers;
  final Map<String, Object?> body;

  String? get auth => headers.value(HttpHeaders.authorizationHeader);
}

/// Starts a loopback server answering each request with [respond]'s body,
/// which may set a status or headers on the way.
Future<_Server> _serve(
  FutureOr<String> Function(HttpRequest request) respond,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final recorder = _Server(server);

  unawaited(
    server.forEach((request) async {
      final bytes = await request.fold<List<int>>(
        <int>[],
        (a, s) => a..addAll(s),
      );
      recorder.requests.add(
        _Request(
          request.uri,
          request.headers,
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>,
        ),
      );
      if (!recorder.arrived.isCompleted) recorder.arrived.complete();
      request.response.write(await respond(request));
      await request.response.close();
    }),
  );
  return recorder;
}

/// The common case: any request gets audio.
FutureOr<String> _audio(HttpRequest request) => 'audio';

void main() {
  group('base_url', () {
    test('appends /audio/speech and normalizes a trailing slash', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await OpenAiSpeechClient().synthesize(
        model: 'm',
        voice: null,
        input: 'hi',
        responseFormat: 'mp3',
        settings: {...server.block, 'base_url': '${server.root}/'},
        speed: 1.0,
      );

      expect(server.requests.single.uri.path, '/audio/speech');
    });

    test('is accepted under the `endpoint` alias', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await OpenAiSpeechClient().synthesize(
        model: 'm',
        voice: null,
        input: 'hi',
        responseFormat: 'mp3',
        settings: {'endpoint': server.root},
        speed: 1.0,
      );

      expect(server.requests, hasLength(1));
    });

    test('is required, and the error names the setting', () {
      expect(
        () => OpenAiSpeechClient().synthesize(
          model: 'm',
          voice: null,
          input: 'hi',
          responseFormat: 'mp3',
          settings: const {},
          speed: 1.0,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('base_url'),
          ),
        ),
      );
    });
  });

  group('request shape', () {
    test(
      'carries model, input, format, voice and a non-default speed',
      () async {
        final server = await _serve(_audio);
        addTearDown(server.close);

        await OpenAiSpeechClient().synthesize(
          model: 'hexgrad/kokoro-82m',
          voice: 'bf_emma',
          input: 'The quick brown fox.',
          responseFormat: 'mp3',
          settings: server.block,
          speed: 0.75,
        );

        expect(server.requests.single.body, {
          'model': 'hexgrad/kokoro-82m',
          'input': 'The quick brown fox.',
          'response_format': 'mp3',
          'voice': 'bf_emma',
          'speed': 0.75,
        });
      },
    );

    test('omits speed when the model does not take it', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await OpenAiSpeechClient().synthesize(
        model: 'm',
        voice: 'v',
        input: 'hi',
        responseFormat: 'mp3',
        settings: server.block,
        speed: null,
      );

      expect(server.requests.single.body.containsKey('speed'), isFalse);
    });

    test('sends speed at the 1.0 default when the model takes it', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await OpenAiSpeechClient().synthesize(
        model: 'm',
        voice: 'v',
        input: 'hi',
        responseFormat: 'mp3',
        settings: server.block,
        speed: 1.0,
      );

      expect(server.requests.single.body['speed'], 1.0);
    });

    test('default_voice fills in only a missing voice', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);
      final block = {...server.block, 'default_voice': 'bm_george'};

      for (final voice in [null, 'bf_emma']) {
        await OpenAiSpeechClient().synthesize(
          model: 'm',
          voice: voice,
          input: 'hi',
          responseFormat: 'mp3',
          settings: block,
          speed: 1.0,
        );
      }

      expect(server.requests.first.body['voice'], 'bm_george');
      expect(server.requests.last.body['voice'], 'bf_emma');
    });

    test('maps X-Generation-Id onto generationId', () async {
      final server = await _serve((request) {
        request.response.headers.set('X-Generation-Id', 'gen-1');
        return 'audio';
      });
      addTearDown(server.close);

      final audio = await OpenAiSpeechClient().synthesize(
        model: 'm',
        voice: null,
        input: 'hi',
        responseFormat: 'mp3',
        settings: server.block,
        speed: 1.0,
      );

      expect(audio.generationId, 'gen-1');
      expect(utf8.decode(audio.bytes), 'audio');
    });
  });

  group('credentials', () {
    test('api_key becomes a Bearer token', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await OpenAiSpeechClient().synthesize(
        model: 'm',
        voice: null,
        input: 'hi',
        responseFormat: 'mp3',
        settings: {...server.block, 'api_key': 'sk-test'},
        speed: 1.0,
      );

      expect(server.requests.single.auth, 'Bearer sk-test');
    });

    test('api_key_env reads the named variable from the environment', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await OpenAiSpeechClient(environment: const {'MY_TTS_KEY': 'sk-env'})
          .synthesize(
            model: 'm',
            voice: null,
            input: 'hi',
            responseFormat: 'mp3',
            settings: {...server.block, 'api_key_env': 'MY_TTS_KEY'},
            speed: 1.0,
          );

      expect(server.requests.single.auth, 'Bearer sk-env');
    });

    test('a keyless block sends no Authorization header', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await OpenAiSpeechClient().synthesize(
        model: 'm',
        voice: null,
        input: 'hi',
        responseFormat: 'mp3',
        settings: server.block,
        speed: 1.0,
      );

      expect(server.requests.single.auth, isNull);
    });

    test('providerNeedsApiKey is inferred from the block', () {
      expect(providerNeedsApiKey(const {'base_url': 'x'}), isFalse);
      expect(providerNeedsApiKey(const {'api_key': 'sk'}), isTrue);
      expect(providerNeedsApiKey(const {'api_key_env': 'MY_KEY'}), isTrue);
    });
  });

  group('failures', () {
    test('a retryable status is retried, then succeeds', () async {
      var attempts = 0;
      final server = await _serve((request) {
        if (++attempts == 1) {
          request.response.statusCode = 503;
          return 'try again';
        }
        return 'audio';
      });
      addTearDown(server.close);

      final audio = await OpenAiSpeechClient.immediateBackoff().synthesize(
        model: 'm',
        voice: null,
        input: 'hi',
        responseFormat: 'mp3',
        settings: server.block,
        speed: 1.0,
      );

      expect(attempts, 2);
      expect(utf8.decode(audio.bytes), 'audio');
    });

    test('a non-retryable status throws without retrying', () async {
      final server = await _serve((request) {
        request.response.statusCode = 401;
        return 'bad key';
      });
      addTearDown(server.close);

      await expectLater(
        OpenAiSpeechClient().synthesize(
          model: 'm',
          voice: null,
          input: 'hi',
          responseFormat: 'mp3',
          settings: server.block,
          speed: 1.0,
        ),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            allOf(contains('401'), contains('bad key')),
          ),
        ),
      );
      expect(server.requests, hasLength(1));
    });
  });

  group('AbortToken', () {
    test('an already-cancelled token aborts before any network call', () {
      expect(
        () => OpenAiSpeechClient().synthesize(
          model: 'm',
          voice: null,
          input: 'hi',
          responseFormat: 'mp3',
          settings: const {'base_url': 'http://localhost:1'},
          speed: 1.0,
          abort: AbortToken()..cancel(),
        ),
        throwsA(isA<AbortException>()),
      );
    });

    test('cancelling in flight aborts the live HTTP call', () async {
      // Never respond: hold the connection open until the client aborts.
      final server = await _serve((_) => Completer<String>().future);
      final token = AbortToken();

      final future = OpenAiSpeechClient().synthesize(
        model: 'm',
        voice: null,
        input: 'hi',
        responseFormat: 'mp3',
        settings: server.block,
        speed: 1.0,
        abort: token,
      );
      await server.arrived.future;
      token.cancel();

      await expectLater(future, throwsA(isA<AbortException>()));
      await server.close();
    });
  });
}
