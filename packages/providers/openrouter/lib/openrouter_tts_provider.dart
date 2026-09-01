import 'dart:convert';
import 'dart:io';

import 'package:tts_narrator_core/tts_narrator_core.dart';

const _endpoint = 'https://openrouter.ai/api/v1/audio/speech';

/// OpenRouter TTS provider: a fold of the former `TtsClient` behind the
/// generic [TtsProvider] interface. Owns everything OpenRouter-specific —
/// endpoint, Bearer auth, retries, and the `X-Generation-Id` mapping.
class OpenRouterTtsProvider implements TtsProvider {
  OpenRouterTtsProvider({this.environment});

  /// Injectable env map (defaults to [Platform.environment]) so tests can run
  /// hermetic without a real API key or network access.
  final Map<String, String>? environment;

  @override
  String get id => 'openrouter';

  @override
  String get name => 'OpenRouter';

  /// Model plugin UI: models with the config's `prompt_style` flag understand
  /// accent/style/prefix/[calm] directives woven into the text, so declare
  /// those styling options for them and nothing otherwise. Keyed off the model
  /// request shape (`TtsModelProfile.promptStyle`) so it survives any alias or
  /// model-id change; interface docs re `TtsProvider.modelUiSpecFor`.
  @override
  ModelUiSpec modelUiSpecFor(TtsModelProfile model) {
    if (!model.promptStyle) return const ModelUiSpec.empty();
    return const ModelUiSpec([
      ModelUiOption(
        key: 'accent',
        label: 'Accent',
        hint: 'e.g., Southern British English',
      ),
      ModelUiOption(
        key: 'style',
        label: 'Style / register',
        hint: 'e.g., Warm, composed, literary',
      ),
      ModelUiOption(
        key: 'passagePrefix',
        label: 'Passage prefix',
        hint: 'An opening directive woven into the first passage, read aloud '
            'before the story starts.',
        type: ModelUiOptionType.multiline,
      ),
      ModelUiOption(
        key: 'useCalmTag',
        label: 'Prepend [calm] directive',
        type: ModelUiOptionType.bool,
      ),
    ]);
  }

  /// Resolves the API key from the run's resolved [settings] (generic rule
  /// applied in core), falling back to the OPENROUTER_API_KEY env var.
  ///
  /// Precedence: `api_key` > `OPENROUTER_API_KEY` > env. Throws naming the
  /// missing source so callers know what to fix.
  String _apiKey(Map<String, String> settings) {
    for (final key in const ['api_key', 'OPENROUTER_API_KEY']) {
      final value = settings[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    final env = (environment ?? Platform.environment)['OPENROUTER_API_KEY'];
    if (env != null && env.trim().isNotEmpty) return env.trim();
    throw StateError(
      'No OpenRouter API key set. Provide it via the "api_key" or '
      '"OPENROUTER_API_KEY" provider settings in the voice config, or set '
      'the OPENROUTER_API_KEY environment variable.',
    );
  }

  /// Synthesizes [input] as audio in [responseFormat], optionally choosing a
  /// [voice], returning the raw bytes. Retries on transient 5xx / empty-stream
  /// failures (a documented Gemini TTS quirk).
  ///
  /// [abort] is checked between retries (and before the first attempt); an
  /// already-cancelled token throws [AbortException] without calling the API.
  @override
  Future<ProviderAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
    AbortToken? abort,
  }) async {
    final key = _apiKey(settings);

    final body = <String, Object?>{
      'model': model,
      'input': input,
      'response_format': responseFormat,
    };
    if (voice != null && voice.isNotEmpty) {
      body['voice'] = voice;
    }

    var attempt = 0;
    while (true) {
      abort?.throwIfCancelled();
      attempt++;
      final (statusCode, bytes, generationId) =
          await _post(jsonEncode(body), key);
      abort?.throwIfCancelled();
      if (statusCode >= 200 && statusCode < 300) {
        if (bytes.isEmpty) {
          if (attempt <= _retries) {
            await _backoff(attempt);
            continue;
          }
          throw HttpException('Empty audio stream after $attempt attempts.');
        }
        return ProviderAudio(bytes: bytes, generationId: generationId);
      }
      // Non-2xx: fail fast unless 5xx (retryable).
      if (statusCode == 502 || statusCode == 500 || statusCode == 503 ||
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

  Future<(int, List<int>, String?)> _post(
    String body,
    String key,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_endpoint));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
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
      client.close(force: true);
    }
  }

  Future<void> _backoff(int attempt) async {
    await Future<void>.delayed(Duration(seconds: 2 * attempt));
  }
}