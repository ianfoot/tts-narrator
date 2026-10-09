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

/// Synthesizes against [server], supplying the arguments every request here
/// shares so that each call below reads as the arguments actually under test.
///
/// [settings] defaults to the server's own provider block; pass one only to
/// exercise an alias or a smuggled key. The future is returned rather than
/// awaited so a test can assert on how a request *fails*, not only on what
/// comes back.
Future<GeneratedAudio> _speak(
  _Server server, {
  String model = 'm',
  String? voice,
  String input = 'hi',
  TtsAudioFormat format = TtsAudioFormat.mp3,
  TtsWavResponseFormat wavFormat = TtsWavResponseFormat.wav,
  Map<String, String>? settings,
  double? speed = 1.0,
  String? language,
  String? instruct,
  String? apiKey,
  AbortToken? abort,
  bool immediateBackoff = false,
}) => (immediateBackoff
        ? OpenAiSpeechClient.immediateBackoff()
        : OpenAiSpeechClient())
    .synthesize(
      model: model,
      voice: voice,
      input: input,
      responseFormat: format,
      wavResponseFormat: wavFormat,
      settings: settings ?? server.block,
      speed: speed,
      language: language,
      instruct: instruct,
      apiKey: apiKey,
      abort: abort,
    );

void main() {
  group('base_url', () {
    test('appends /audio/speech and normalizes a trailing slash', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await _speak(
        server,
        settings: {...server.block, 'base_url': '${server.root}/'},
      );

      expect(server.requests.single.uri.path, '/audio/speech');
    });

    test('is accepted under the `endpoint` alias', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await _speak(server, settings: {'endpoint': server.root});

      expect(server.requests, hasLength(1));
    });

    test('is required, and the error names the setting', () {
      expect(
        () => OpenAiSpeechClient().synthesize(
          model: 'm',
          voice: null,
          input: 'hi',
          responseFormat: TtsAudioFormat.mp3,
          wavResponseFormat: TtsWavResponseFormat.wav,
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

        await _speak(
          server,
          model: 'hexgrad/kokoro-82m',
          voice: 'bf_emma',
          input: 'The quick brown fox.',
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

      await _speak(server, voice: 'v', speed: null);

      expect(server.requests.single.body.containsKey('speed'), isFalse);
    });

    test('default_voice fills in only a missing voice', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);
      final block = {...server.block, 'default_voice': 'bm_george'};

      for (final voice in [null, 'bf_emma']) {
        await _speak(server, voice: voice, settings: block);
      }

      expect(server.requests.first.body['voice'], 'bm_george');
      expect(server.requests.last.body['voice'], 'bf_emma');
    });

    test('carries lang_code when a language is chosen', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await _speak(
        server,
        model: 'hexgrad/kokoro-82m',
        voice: 'jm_kumo',
        language: 'j',
      );

      expect(server.requests.single.body['lang_code'], 'j');
    });

    test('omits lang_code for a null or empty language', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      for (final language in [null, '']) {
        await _speak(server, voice: 'v', language: language);
      }

      for (final request in server.requests) {
        expect(request.body.containsKey('lang_code'), isFalse);
      }
    });

    test(
      'carries instruct when a voice design describes the narrator',
      () async {
        final server = await _serve(_audio);
        addTearDown(server.close);

        await _speak(
          server,
          model: 'mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16',
          format: TtsAudioFormat.wav,
          instruct: '  A calm, low British male narrator.  ',
        );

        expect(
          server.requests.single.body['instruct'],
          'A calm, low British male narrator.',
        );
      },
    );

    test('omits instruct for a null, empty or whitespace-only value', () async {
      // An empty instruct is not a request for the vendor's default voice: it
      // describes no voice at all, so the field is dropped rather than sent blank.
      final server = await _serve(_audio);
      addTearDown(server.close);

      for (final instruct in [null, '', '   ']) {
        await _speak(server, voice: 'v', instruct: instruct);
      }

      expect(server.requests, hasLength(3));
      for (final request in server.requests) {
        expect(request.body.containsKey('instruct'), isFalse);
      }
    });

    test('maps X-Generation-Id onto generationId', () async {
      final server = await _serve((request) {
        request.response.headers.set('X-Generation-Id', 'gen-1');
        return 'audio';
      });
      addTearDown(server.close);

      final audio = await _speak(server);

      expect(audio.generationId, 'gen-1');
      expect(utf8.decode(audio.bytes), 'audio');
    });
  });

  group('credentials', () {
    // The client no longer reads `api_key` from the settings block: the
    // credential arrives as the `apiKey` argument, resolved by the caller. That
    // split is what keeps it out of `providerSettings`, and it means these tests
    // are about transport only — literal-vs-`${ENV}` resolution is
    // `resolveProviderApiKey`'s job, tested in provider_settings_test.dart.
    test('apiKey becomes a Bearer token', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await _speak(server, apiKey: 'sk-test');

      expect(server.requests.single.auth, 'Bearer sk-test');
    });

    test('a null apiKey sends no Authorization header', () async {
      final server = await _serve(_audio);
      addTearDown(server.close);

      await _speak(server);

      expect(server.requests.single.auth, isNull);
    });

    test('an api_key left in the settings block is never sent', () async {
      // Guards the split: a secret smuggled through `providerSettings` would
      // be silently dropped, which is the point — but it must not also be sent.
      final server = await _serve(_audio);
      addTearDown(server.close);

      await _speak(server, settings: {...server.block, 'api_key': 'sk-leaked'});

      expect(server.requests.single.auth, isNull);
    });
  });

  group('auth failures', () {
    Future<HttpException> rejectWith(
      int status, {
      required bool withKey,
    }) async {
      final server = await _serve((request) {
        request.response.statusCode = status;
        return '{"error":"unauthorized"}';
      });
      addTearDown(server.close);
      try {
        await _speak(
          server,
          immediateBackoff: true,
          apiKey: withKey ? 'sk-rejected' : null,
        );
        fail('expected an HttpException');
      } on HttpException catch (e) {
        return e;
      }
    }

    for (final status in const [401, 403]) {
      test('HTTP $status with no key tells the user to add one', () async {
        final e = await rejectWith(status, withKey: false);
        expect(e.message, contains('No API key was configured'));
        expect(e.message, contains('add one in Settings'));
      });

      test('HTTP $status with a key says the key was rejected', () async {
        final e = await rejectWith(status, withKey: true);
        expect(e.message, contains('rejected the API key that was sent'));
        // Crucially *not* the "you have no key" advice, which would send a
        // user with a stale key in circles.
        expect(e.message, isNot(contains('No API key was configured')));
      });
    }

    test('a non-auth failure keeps the vendor message verbatim', () async {
      final server = await _serve((request) {
        request.response.statusCode = 429;
        return '{"error":"quota exceeded"}';
      });
      addTearDown(server.close);

      try {
        await _speak(server, immediateBackoff: true, apiKey: 'sk-test');
        fail('expected an HttpException');
      } on HttpException catch (e) {
        expect(e.message, contains('quota exceeded'));
        expect(e.message, isNot(contains('API key')));
      }
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

      final audio = await _speak(server, immediateBackoff: true);

      expect(attempts, 2);
      expect(utf8.decode(audio.bytes), 'audio');
    });

    test('a non-retryable status throws without retrying', () async {
      final server = await _serve((request) {
        request.response.statusCode = 400;
        return 'bad request';
      });
      addTearDown(server.close);

      await expectLater(
        _speak(server),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            allOf(contains('400'), contains('bad request')),
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
          responseFormat: TtsAudioFormat.mp3,
          wavResponseFormat: TtsWavResponseFormat.wav,
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

      final future = _speak(server, abort: token);
      await server.arrived.future;
      token.cancel();

      await expectLater(future, throwsA(isA<AbortException>()));
      await server.close();
    });
  });
}
