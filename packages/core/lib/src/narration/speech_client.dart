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

  /// Optional provider generation/correlation metadata (`X-Generation-Id` in the
  /// OpenAI protocol). Not yet wired into the manifest.
  final String? generationId;
}

/// Requests audio for one model of text.
///
/// This is the seam between "how audio is produced" and "what is narrated":
/// an entrypoint injects the client it was configured for, and `narrate` calls
/// it. Adding a vendor therefore means adding a config block, not a package.
///
/// Deliberately a function type and not an interface: every provider speaks the
/// same OpenAI `/audio/speech` protocol, so an interface here would have one
/// implementor forever. A function keeps the seam that lets tests hand `narrate`
/// a closure instead of standing up an HTTP server.
///
/// [settings] is the run's resolved provider block and deliberately carries no
/// secret: the credential travels beside it as [apiKey], resolved by the caller,
/// the only layer that can reach the OS keychain. A null key means no
/// `Authorization` header, not an error — whether one was *needed* is the
/// server's judgement.
///
/// [voice], [speed], [language] and [instruct] are capability-gated by the model
  /// profile, and null when it does not take them; see `TtsModelProfile` for what
  /// each means and which model flag gates it.
///
/// [abort] is checked before the first attempt and between retries: an
/// already-cancelled token throws [AbortException] without calling the API.
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
