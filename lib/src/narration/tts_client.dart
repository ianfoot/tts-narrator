import 'dart:convert';
import 'dart:io';

const _endpoint = 'https://openrouter.ai/api/v1/audio/speech';

/// A generated audio sample with metadata for the manifest.
class NarrationSample {
  NarrationSample({
    required this.wavPath,
    required this.generationId,
    required this.bytes,
  });

  final String wavPath;
  final String? generationId;
  final int bytes;
}

/// Minimal HTTP client for the OpenRouter `/audio/speech` endpoint.
class TtsClient {
  TtsClient({this.apiKey});

  /// OpenRouter API key; falls back to OPENROUTER_API_KEY when null.
  final String? apiKey;

  /// Synthesize [input] as PCM audio (16-bit little-endian, 24 kHz mono),
  /// returning the raw bytes. Retries on transient 5xx / empty-stream
  /// failures (a documented Gemini TTS quirk).
  Future<List<int>> synthesize({
    required String model,
    required String voice,
    required String input,
    int retries = 3,
  }) async {
    final key = apiKey ?? Platform.environment['OPENROUTER_API_KEY'];
    if (key == null || key.isEmpty) {
      throw StateError('No API key set (OPENROUTER_API_KEY or --api-key).');
    }

    final body =
        jsonEncode({
          'model': model,
          'input': input,
          'voice': voice,
          'response_format': 'pcm',
        });

    var attempt = 0;
    while (true) {
      attempt++;
      final (statusCode, bytes, generationId) = await _post(body, key);
      if (statusCode >= 200 && statusCode < 300) {
        if (bytes.isEmpty) {
          if (attempt <= retries) {
            await _backoff(attempt);
            continue;
          }
          throw HttpException('Empty audio stream after $attempt attempts.');
        }
        return bytes;
      }
      // Non-2xx: fail fast unless 5xx (retryable).
      if (statusCode == 502 || statusCode == 500 || statusCode == 503 ||
          statusCode == 529) {
        if (attempt <= retries) {
          await _backoff(attempt);
          continue;
        }
      }
      final message = utf8.decode(bytes, allowMalformed: true);
      throw HttpException('TTS request failed (HTTP $statusCode): $message');
    }
  }

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
        (acc, chunk) => acc..addAll(chunk),
      );
      return (response.statusCode, bytes, response.headers.value('X-Generation-Id'));
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _backoff(int attempt) async {
    await Future<void>.delayed(Duration(seconds: 2 * attempt));
  }
}