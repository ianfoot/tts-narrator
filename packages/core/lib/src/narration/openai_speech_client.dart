import 'dart:convert';
import 'dart:io';

import 'abort.dart';
import 'speech_client.dart';

/// The client for every OpenAI-compatible `/audio/speech` service.
///
/// Both former providers differed only in a default URL, an optional Bearer
/// token, and a default voice — none of which is worth a class. This client is
/// that shared protocol: the vendor identity lives entirely in the config
/// block, so pointing core at a new speech service is a config edit.
///
/// Nothing is synthesized locally — the vendor does that. This speaks a wire
/// protocol and hands back audio bytes.
///
/// Retry, backoff, abort and HTTP plumbing are collapsed here rather than
/// duplicated per vendor.
class OpenAiSpeechClient {
  /// Attempts allowed *after* the first, i.e. 4 requests in the worst case.
  static const _retries = 3;

  /// Injectable env map (defaults to [Platform.environment]) so tests can run
  /// hermetic without real credentials.
  final Map<String, String>? environment;

  /// Delay before retry [attempt] (1-based). Injected so tests exercising the
  /// retry path don't pay real wall-clock; production uses [defaultBackoff].
  final Duration Function(int attempt) backoff;

  /// Creates a client, optionally with a hermetic environment map and a custom
  /// [backoff].
  OpenAiSpeechClient({
    this.environment,
    Duration Function(int attempt)? backoff,
  }) : backoff = backoff ?? defaultBackoff;

  /// Linear backoff: 2s, 4s, 6s. Deliberately real time — a narration run can
  /// afford to wait out a flaky vendor.
  static Duration defaultBackoff(int attempt) => Duration(seconds: 2 * attempt);

  Future<GeneratedAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
    required double? speed,
    AbortToken? abort,
  }) async {
    final uri = _speechUri(settings);
    final key = _apiKey(settings);
    // An explicit voice always wins; `default_voice` only fills the gap.
    final requestedVoice = (voice == null || voice.isEmpty) ? null : voice;
    final resolvedVoice = requestedVoice ?? _defaultVoice(settings);

    final body = <String, Object?>{
      'model': model,
      'input': input,
      'response_format': responseFormat,
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

    var attempt = 0;
    while (true) {
      abort?.throwIfCancelled();
      attempt++;
      final (statusCode, bytes, generationId) = await _runAttempt(
        jsonEncode(body),
        uri,
        key,
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
        return GeneratedAudio(bytes: bytes, generationId: generationId);
      }
      // Non-2xx: fail fast unless retryable.
      if (_isRetryable(statusCode) && attempt <= _retries) {
        await Future<void>.delayed(backoff(attempt));
        continue;
      }
      final message = utf8.decode(bytes, allowMalformed: true);
      throw HttpException('TTS request failed (HTTP $statusCode): $message');
    }
  }

  /// Builds the speech URL from the block's `base_url` (alias `endpoint`).
  ///
  /// `base_url` is a **root** — the vendor path is appended here, so a config
  /// block carries `https://openrouter.ai/api/v1`, not the full speech URL.
  /// `endpoint` is accepted as a documented alias for the same value.
  Uri _speechUri(Map<String, String> settings) {
    final root = settings['base_url'] ?? settings['endpoint'];
    final trimmed = root?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      // Names the setting, not the block: the block name is not available on
      // this call path.
      throw StateError(
        'TTS provider block is missing required setting "base_url" '
        '(the speech endpoint root, e.g. "https://openrouter.ai/api/v1").',
      );
    }
    final withoutSlash = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return Uri.parse('$withoutSlash/audio/speech');
  }

  /// Resolves the Bearer token, or null when the block is keyless.
  ///
  /// Precedence: `api_key`/`apiKey` (a literal or an already-resolved `${ENV}`
  /// value) then `api_key_env`, whose value is the *name* of an environment
  /// variable to read from [environment]. A block with neither sends no
  /// `Authorization` header at all, which is the norm for local servers.
  String? _apiKey(Map<String, String> settings) {
    for (final name in const ['api_key', 'apiKey']) {
      final value = settings[name];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    final envName = settings['api_key_env']?.trim();
    if (envName != null && envName.isNotEmpty) {
      final value = (environment ?? Platform.environment)[envName];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
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
  /// A genuine [AbortException] (from a pre-cancelled token) passes through;
  /// any I/O error raised by the force-close on cancel is reported as an abort
  /// rather than a connection failure.
  Future<(int, List<int>, String?)> _runAttempt(
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

  Future<(int, List<int>, String?)> _post(
    String body,
    Uri uri,
    String? key, {
    AbortToken? abort,
  }) async {
    final client = HttpClient();
    // On cancel, force-close the live connection so the in-flight read is
    // terminated instead of left billing a stalled response. Unsubscribed once
    // this request settles; a later cancel of the same token (e.g. for a
    // retry) registers a fresh hook.
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
      );
    } finally {
      unsubscribe?.call();
      client.close(force: true);
    }
  }

  /// A client whose retries do not wait, for tests.
  factory OpenAiSpeechClient.immediateBackoff({
    Map<String, String>? environment,
  }) => OpenAiSpeechClient(
    environment: environment,
    backoff: (_) => Duration.zero,
  );
}