import 'dart:convert';
import 'dart:io';

import 'package:tts_narrator_core/tts_narrator_core.dart';

const _endpoint = 'http://localhost:8000/v1/audio/speech';

/// Default model id used when the profile does not specify one (the classic
/// MLX Kokoro deployment served by the mlx-audio server).
const _defaultModel = 'mlx-community/Kokoro-82M-bf16';

const _defaultVoice = 'bm_george';

/// Local OpenAI-compatible TTS provider (legacy id `mlx_audio`).
///
/// Talks to any OpenAI-compatible `/v1/audio/speech` server via HTTP; the
/// classic target is the local mlx-audio server (Apple Silicon, no API key).
/// The endpoint and model come from config (per-profile `provider` settings),
/// so other local or remote compatible services work without code changes.
class MlxAudioTtsProvider implements TtsProvider {
  MlxAudioTtsProvider({this.endpoint});

  /// Injectable endpoint (defaults to the local speech URL) so tests can point
  /// the provider at a local server. Provider settings (`endpoint`) take
  /// precedence over this constructor value.
  final String? endpoint;

  @override
  String get id => 'mlx_audio';

  @override
  String get name => 'Local OpenAI-compatible';

  /// Model plugin UI: the model has no prompt styling, but it exposes a
  /// `speed` control (the server accepts a speech-rate multiplier) for any
  /// kokoro-family model id.
  @override
  ModelUiSpec modelUiSpecFor(TtsModelProfile model) {
    if (model.id.toLowerCase().contains('kokoro')) {
      return const ModelUiSpec([
        ModelUiControl(
          key: 'speed',
          label: 'Speed',
          type: ModelUiOptionType.speed,
        ),
      ]);
    }
    return const ModelUiSpec.empty();
  }

  /// Synthesizes [input] as audio, optionally choosing a [voice] (defaults to
  /// [defaultVoice]) at a [speed] multiplier (1.0 = normal), returning the raw
  /// bytes. Retries on transient 5xx / empty-stream failures.
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
    double speed = 1.0,
    AbortToken? abort,
  }) async {
    final resolvedModel = model.trim().isEmpty ? _defaultModel : model;
    final resolvedVoice = (voice == null || voice.isEmpty) ? _defaultVoice : voice;
    final resolvedEndpoint = settings['endpoint'] ?? endpoint ?? _endpoint;
    final body = <String, Object?>{
      'model': resolvedModel,
      'input': input,
      'voice': resolvedVoice,
      'response_format': responseFormat,
      'speed': speed,
    };
    final apiKey = settings['api_key'] ?? settings['apiKey'];

    var attempt = 0;
    while (true) {
      abort?.throwIfCancelled();
      attempt++;
      final (statusCode, bytes, generationId) = await _runAttempt(
        body,
        endpoint: resolvedEndpoint,
        apiKey: apiKey,
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
    required String endpoint,
    String? apiKey,
    AbortToken? abort,
  }) async {
    try {
      return await _post(
        jsonEncode(body),
        endpoint: endpoint,
        apiKey: apiKey,
        abort: abort,
      );
    } on AbortException {
      rethrow;
    } catch (_) {
      if (abort?.cancelled == true) throw AbortException();
      rethrow;
    }
  }

  Future<(int, List<int>, String?)> _post(
    String body, {
    required String endpoint,
    String? apiKey,
    AbortToken? abort,
  }) async {
    final client = HttpClient();
    // On cancel, force-close the live connection so the in-flight read is
    // terminated instead of left hanging on a stalled response. Unsubscribed
    // once this request settles; a later cancel of the same token (e.g. for a
    // retry) registers a fresh hook.
    final unsubscribe = abort?.onCancel(() => client.close(force: true));
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.contentType = ContentType.json;
      if (apiKey != null && apiKey.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
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