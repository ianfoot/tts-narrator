import 'dart:convert';
import 'dart:io';

import 'package:tts_narrator_core/tts_narrator_core.dart';

const _endpoint = 'http://localhost:8000/v1/audio/speech';

/// MLX Audio TTS provider: a local service for the MLX Kokoro model.
/// Synthesizes via the local MLX audio server (default localhost:8000) using
/// the Kokoro model (mlx-community/Kokoro-82M-bf16) with no API key.
class MlxAudioTtsProvider implements TtsProvider {
  MlxAudioTtsProvider({this.endpoint});

  /// Injectable endpoint (defaults to the local MLX audio speech URL) so
  /// tests can point the provider at a local server.
  final String? endpoint;

  @override
  String get id => 'mlx_audio';

  @override
  String get name => 'MLX Audio';

  /// Model plugin UI: the MLX Kokoro model has fixed voices and no prompt
  /// styling, so it declares no options.
  @override
  ModelUiSpec modelUiSpecFor(TtsModelProfile model) =>
      const ModelUiSpec.empty();

  /// Synthesizes [input] as audio, optionally choosing a [voice] (defaults to
  /// the model's `bm_george` voice), returning the raw bytes. Retries on
  /// transient 5xx / empty-stream failures.
  ///
  /// [abort] is checked between retries (and before the first attempt); an
  /// already-cancelled token throws [AbortException] without calling the API.
  @override
  Future<GeneratedAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
    AbortToken? abort,
  }) async {
    final body = <String, Object?>{
      'model': 'mlx-community/Kokoro-82M-bf16',
      'input': input,
      'voice': voice ?? 'bm_george',
      'response_format': 'mp3',
      'speed': 0.8,
    };

    var attempt = 0;
    while (true) {
      abort?.throwIfCancelled();
      attempt++;
      final (statusCode, bytes, generationId) = await _runAttempt(
        body,
        abort: abort,
      );
      abort?.throwIfCancelled();
      if (statusCode >= 200 && statusCode < 300) {
        if (bytes.isEmpty) {
          if (attempt <= _retries) {
            await _backoff(attempt);
            continue;
          }
          throw HttpException('Empty audio stream after $attempt attempts.');
        }
        return GeneratedAudio(bytes: bytes, generationId: generationId);
      }
      // Non-2xx: fail fast unless 5xx (retryable).
      if (statusCode == 502 ||
          statusCode == 500 ||
          statusCode == 503 ||
          statusCode == 529) {
        if (attempt <= _retries) {
          await _backoff(attempt);
          continue;
        }
      }
      final message = utf8.decode(bytes, allowMalformed: true);
      throw HttpException('TTS request failed (HTTP $statusCode): $message');
    }
  }

  static const _retries = 3;

  /// Runs a single attempt at [body], normalizing a cancellation-induced
  /// mid-request failure into [AbortException] so the run unwinds cleanly.
  ///
  /// A genuine [AbortException] (from a pre-cancelled token) passes through;
  /// any I/O error raised by the force-close on cancel is reported as an
  /// abort rather than a connection failure.
  Future<(int, List<int>, String?)> _runAttempt(
    Map<String, Object?> body, {
    AbortToken? abort,
  }) async {
    try {
      return await _post(jsonEncode(body), abort: abort);
    } on AbortException {
      rethrow;
    } catch (_) {
      if (abort?.cancelled == true) throw AbortException();
      rethrow;
    }
  }

  Future<(int, List<int>, String?)> _post(
    String body, {
    AbortToken? abort,
  }) async {
    final client = HttpClient();
    // On cancel, force-close the live connection so the in-flight read is
    // terminated instead of left hanging on a stalled response. Unsubscribed
    // once this request settles; a later cancel of the same token (e.g. for a
    // retry) registers a fresh hook.
    final unsubscribe = abort?.onCancel(() => client.close(force: true));
    try {
      final request = await client.postUrl(Uri.parse(endpoint ?? _endpoint));
      request.headers.contentType = ContentType.json;
      request.write(body);
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (acc, segment) => acc..addAll(segment),
      );
      return (
        response.statusCode,
        bytes,
        response.headers.value('X-Generation-Id'),
      );
    } finally {
      unsubscribe?.call();
      client.close(force: true);
    }
  }

  Future<void> _backoff(int attempt) async {
    await Future<void>.delayed(Duration(seconds: 2 * attempt));
  }
}
