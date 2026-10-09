import 'dart:convert';
import 'dart:io';

import '../config/provider_settings.dart';
import 'abort.dart';
import 'audio_format.dart';
import 'speech_client.dart';

/// The client for every OpenAI-compatible `/audio/speech` service.
///
/// The vendor identity lives entirely in the config block, so pointing core at a
/// new speech service is a config edit. Nothing is synthesized locally; this
/// speaks a wire protocol and hands back audio bytes, with retry, backoff, abort
/// and HTTP plumbing collapsed here rather than duplicated per vendor.
class OpenAiSpeechClient {
  /// Attempts allowed *after* the first, i.e. 4 requests in the worst case.
  static const _retries = 3;

  /// Delay before retry [attempt] (1-based). Injected so tests exercising the
  /// retry path don't pay real wall-clock; production uses [defaultBackoff].
  final Duration Function(int attempt) backoff;

  /// Creates a client with a custom [backoff].
  ///
  /// The credential is per-call, not per-client: [synthesize] takes [apiKey] so
  /// a long-lived client cannot serve a stale secret after the user edits it.
  OpenAiSpeechClient({Duration Function(int attempt)? backoff})
    : backoff = backoff ?? defaultBackoff;

  /// Linear backoff: 2s, 4s, 6s. Deliberately real time — a narration run can
  /// afford to wait out a flaky vendor.
  static Duration defaultBackoff(int attempt) => Duration(seconds: 2 * attempt);

  /// Bearer token for this call, or null to send no `Authorization` header.
  ///
  /// Null is a legitimate outcome: whether a key is *required* is the server's
  /// call, so the client never blocks a run over a missing credential. [settings]
  /// is the run's resolved provider block.
  Future<GeneratedAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required TtsAudioFormat responseFormat,
    required TtsWavResponseFormat wavResponseFormat,
    required Map<String, String> settings,
    required double? speed,
    String? language,
    String? instruct,
    String? apiKey,
    AbortToken? abort,
  }) async {
    final uri = _speechUri(settings);
    // An explicit voice always wins; `default_voice` only fills the gap.
    final requestedVoice = (voice == null || voice.isEmpty) ? null : voice;
    final resolvedVoice = requestedVoice ?? _defaultVoice(settings);

    final body = <String, Object?>{
      'model': model,
      'input': input,
      // A wav run asks for whatever this model serves WAV as.
      'response_format': responseFormat == TtsAudioFormat.wav
          ? wavResponseFormat.wireValue
          : responseFormat.wireValue,
    };
    if (resolvedVoice != null && resolvedVoice.isNotEmpty) {
      body['voice'] = resolvedVoice;
    }
    // Capability-gated by the model profile: a model that declares
    // `"speed": true` always gets the field, including the 1.0 default, so a
    // capable model never has to infer "unset" from a missing key.
    if (speed != null) {
      body['speed'] = speed;
    }
    // Kokoro's language selector, redundant with the voice id by design but what
    // the API documents; sending it keeps the request self-describing.
    if (language != null && language.isNotEmpty) {
      body['lang_code'] = language;
    }
    // Qwen3 Voice Design synthesizes a voice from prose rather than picking one
    // from a list, so `instruct` replaces `voice`. Sent only when non-empty: an
    // empty string would be a different (and meaningless) request from omitting
    // the field.
    if (instruct != null && instruct.trim().isNotEmpty) {
      body['instruct'] = instruct.trim();
    }

    var attempt = 0;
    while (true) {
      abort?.throwIfCancelled();
      attempt++;
      final (statusCode, bytes, generationId, contentType) = await _runAttempt(
        jsonEncode(body),
        uri,
        apiKey,
        abort: abort,
      );
      abort?.throwIfCancelled();
      if (statusCode >= 200 && statusCode < 300) {
        if (bytes.isEmpty) {
          // A documented upstream quirk: 2xx with no audio is retryable.
          if (attempt <= _retries) {
            await Future<void>.delayed(backoff(attempt));
            continue;
          }
          throw HttpException('Empty audio stream after $attempt attempts.');
        }
        return GeneratedAudio(
          bytes: bytes,
          generationId: generationId,
          sampleRate: _parameter(contentType, 'rate'),
          channels: _parameter(contentType, 'channels'),
        );
      }
      // Non-2xx: fail fast unless retryable.
      if (_isRetryable(statusCode) && attempt <= _retries) {
        await Future<void>.delayed(backoff(attempt));
        continue;
      }
      final message = utf8.decode(bytes, allowMalformed: true);
      throw HttpException(
        'TTS request failed (HTTP $statusCode): '
        '${_authGuidance(statusCode, apiKey) ?? message}',
      );
    }
  }

  /// Extra guidance for a 401/403, or null when the status is not an auth
  /// rejection.
  ///
  /// The vendor's own error text is *replaced* rather than appended: it is
  /// usually a terse "No auth credentials found", and the actionable half is
  /// which of the two situations the user is in — a rejected key and a missing
  /// key need different fixes.
  String? _authGuidance(int statusCode, String? apiKey) {
    if (statusCode != 401 && statusCode != 403) return null;
    return apiKey == null || apiKey.isEmpty
        ? 'The provider rejected the request as unauthenticated. No API key '
              'was configured, so none was sent — add one in Settings, or set '
              'api_key in the provider config block.'
        : 'The provider rejected the API key that was sent. Check that the '
              'key is current and belongs to this account.';
  }

  /// Builds the speech URL from the block's `base_url` (alias `endpoint`).
  ///
  /// `base_url` is a **root** — the vendor path is appended here, so a config
  /// block carries `https://vendor.example/api/v1`, not the full speech URL.
  /// `endpoint` is accepted as a documented alias for the same value. The
  /// lookup is shared with [narrate] via [providerBaseUrl].
  Uri _speechUri(Map<String, String> settings) {
    final trimmed = providerBaseUrl(settings);
    if (trimmed == null) {
      // Backstop only: `narrate` validates before the first segment, so reaching
      // here means the client was called directly.
      throw StateError(
        'TTS provider block is missing required setting "base_url" '
        '(the speech endpoint root, e.g. "https://vendor.example/api/v1").',
      );
    }
    final withoutSlash = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return Uri.parse('$withoutSlash/audio/speech');
  }

  /// The block's `default_voice`, used when the request carries no [voice].
  String? _defaultVoice(Map<String, String> settings) =>
      settings['default_voice']?.trim();

  static bool _isRetryable(int statusCode) =>
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 529;

  /// Runs a single attempt, normalizing a cancellation-induced mid-request
  /// failure into [AbortException] so the run unwinds cleanly.
  ///
  /// A genuine [AbortException] passes through; any I/O error raised by the
  /// force-close on cancel is reported as an abort rather than a connection
  /// failure.
  Future<(int, List<int>, String?, String?)> _runAttempt(
    String body,
    Uri uri,
    String? key, {
    AbortToken? abort,
  }) async {
    try {
      return await _post(body, uri, key, abort: abort);
    } on AbortException {
      rethrow;
    } catch (_) {
      if (abort?.cancelled == true) throw AbortException();
      rethrow;
    }
  }

  Future<(int, List<int>, String?, String?)> _post(
    String body,
    Uri uri,
    String? key, {
    AbortToken? abort,
  }) async {
    final client = HttpClient();
    // On cancel, force-close the live connection so the in-flight read is
    // terminated rather than left billing a stalled response.
    final unsubscribe = abort?.onCancel(() => client.close(force: true));
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (key != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
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
        response.headers.value(HttpHeaders.contentTypeHeader),
      );
    } finally {
      unsubscribe?.call();
      client.close(force: true);
    }
  }

  /// Reads a numeric parameter out of a `Content-Type` header.
  ///
  /// A provider states the audio's shape in its response type — `audio/pcm;rate=
  /// 24000;channels=1` is what OpenRouter sends for headerless samples. That is
  /// the only place the rate is knowable for bytes arriving with no header of
  /// their own. Returns null when the header is absent or carries no such
  /// parameter, leaving [sampleRate] unset rather than guessing.
  int? _parameter(String? contentType, String name) {
    if (contentType == null) return null;
    for (final part in contentType.split(';').skip(1)) {
      final pieces = part.trim().split('=');
      if (pieces.length != 2) continue;
      if (pieces.first.trim() != name) continue;
      return int.tryParse(pieces.last.trim());
    }
    return null;
  }

  /// A client whose retries do not wait, for tests.
  factory OpenAiSpeechClient.immediateBackoff() =>
      OpenAiSpeechClient(backoff: (_) => Duration.zero);
}
