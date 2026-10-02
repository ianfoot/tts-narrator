import 'abort.dart';

/// Audio bytes returned by a [SpeechClient].
class GeneratedAudio {
  GeneratedAudio({required this.bytes, this.generationId});

  /// Raw audio bytes in the requested format.
  final List<int> bytes;

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
/// [settings] is the run's resolved provider block. [voice] and [speed] are
/// capability-gated by the model profile and are null when the model does not
/// take them: [speed] is a speech-rate multiplier (1.0 = normal), sent only for
/// a model that declares `"speed": true`. [abort] is checked before the first
/// attempt and between retries — an already-cancelled token throws
/// [AbortException] without calling the API.
typedef SpeechClient = Future<GeneratedAudio> Function({
  required String model,
  required String? voice,
  required String input,
  required String responseFormat,
  required Map<String, String> settings,
  required double? speed,
  AbortToken? abort,
});