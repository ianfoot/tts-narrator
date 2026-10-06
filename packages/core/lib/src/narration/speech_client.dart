import 'abort.dart';
import 'audio_format.dart';

/// Audio bytes returned by a [SpeechClient].
class GeneratedAudio {
  GeneratedAudio({
    required this.bytes,
    this.generationId,
    this.sampleRate,
    this.channels,
  });

  /// Raw audio bytes in the requested format.
  final List<int> bytes;

  /// Sample rate of [bytes], when the provider stated it.
  ///
  /// A provider announces this in its response's `Content-Type` — for example
  /// `audio/pcm;rate=24000;channels=1`. It is null when the response did not say,
  /// which matters only when the bytes are headerless samples: a finished WAV
  /// carries its own rate in its header, so this is never consulted there.
  final int? sampleRate;

  /// Channel count of [bytes], when the provider stated it, from the same
  /// `Content-Type` parameter as [sampleRate].
  final int? channels;

  /// Optional provider-specific generation/correlation metadata. The OpenAI
  /// speech protocol returns `X-Generation-Id`; the client maps that header
  /// onto this field. It is generic optional metadata and is not yet wired into
  /// the manifest.
  final String? generationId;
}

/// Requests audio for one model of text.
///
/// This is the seam between "how audio is produced" and "what is narrated":
/// an entrypoint injects the client it was configured for, and `narrate` calls
/// it. Adding a vendor therefore means adding a config block, not a package.
///
/// Named a client rather than a synthesizer because nothing synthesizes
/// locally — the vendor does. This speaks a wire protocol and returns bytes.
///
/// Deliberately a function type and not an interface. Every provider speaks
/// the same OpenAI `/audio/speech` protocol, so there is nothing for a second
/// implementation to vary over — an interface here would have one implementor
/// forever. A function keeps the seam that lets tests hand `narrate` a closure
/// instead of standing up an HTTP server, without an empty hierarchy.
///
/// [settings] is the run's resolved provider block, and deliberately never
/// carries a secret: the credential travels beside it as [apiKey], resolved by
/// the caller, which is the only layer that can reach the OS keychain. [voice]
/// and [speed] are capability-gated by the model profile and are null when the
/// model does not take them: [speed] is a speech-rate multiplier (1.0 = normal),
/// sent only for a model that declares `"speed": true`. [language] is likewise
/// null unless the model declares `"sends_language": true`, and is the short
/// code the provider expects (Kokoro: `lang_code`, the first character of its
/// voice ids). [instruct] is a free-form natural-language description of the
/// voice to synthesize — the field Qwen3 Voice Design takes instead of a voice
/// id — and is null unless the model declares `"sends_instruct": true`.
/// [abort] is checked before the first attempt and between retries — an
/// already-cancelled token throws [AbortException] without calling the API.
///
/// [apiKey] is null when no key is configured; the request then carries no
/// `Authorization` header. Whether one was *needed* is the server's judgement,
/// not the client's, so a null key is not an error here.
///
/// [responseFormat] is the container the run wants on disk. Which wire value
/// that becomes is the client's business, not the caller's: MP3 always goes out
/// as `mp3`, while WAV goes out as `wav` or `pcm` depending on the model
/// (see [TtsWavResponseFormat]). Both live on the model profile, so the
/// disagreement between backends is resolved once when the model file is parsed
/// instead of at request time, and an unsupported value cannot reach the wire.
typedef SpeechClient = Future<GeneratedAudio> Function({
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
});
