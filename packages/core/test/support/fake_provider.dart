import 'package:tts_narrator_core/tts_narrator_core.dart';

/// The `providers.<name>` block name tests put on a [TtsModelProfile].
///
/// Core treats the provider name as opaque config data, so tests need *a* name
/// and nothing more. This is deliberately not a real vendor: the point of the
/// config-driven provider design is that core knows no vendor names, and tests
/// should not reintroduce one by default.
const testProvider = 'fake';

/// The `base_url` tests put in their provider block.
///
/// `narrate` validates the block up front, so a test that drives it needs a
/// usable endpoint root. `.invalid` is reserved by RFC 2606 and can never
/// resolve, which is the point: nothing here should touch the network.
const testBaseUrl = 'https://example.invalid/v1';

/// Records every [synthesize] call and returns configurable bytes, so tests can
/// assert what `narrate` dispatches to the client without any network.
class FakeTtsProvider {
  FakeTtsProvider({List<int>? bytes, this.sampleRate, this.channels})
    : bytes = bytes ?? 'fake-audio'.codeUnits;

  /// Provider label recorded on the profile under test, so a profile and this
  /// fake name the same block. Not part of any interface — core no longer
  /// resolves providers — but tests use it to keep the two in step.
  String get id => testProvider;

  /// Bytes returned by [synthesize].
  final List<int> bytes;

  /// Sample rate reported on the response, as a backend serving raw samples
  /// would. Null models the backends that serve a finished container, where the
  /// rate is inside the payload rather than in a header parameter.
  final int? sampleRate;

  /// Channel count reported on the response, for the same reason.
  final int? channels;

  final List<
    ({
      String model,
      String? voice,
      String input,
      TtsAudioFormat responseFormat,
      TtsWavResponseFormat wavResponseFormat,
      Map<String, String> settings,
      double? speed,
      String? language,
      String? instruct,
      String? apiKey,
    })
  >
  calls = [];

  int get callCount => calls.length;

  /// The seam to hand `narrate`; tees into [calls].
  SpeechClient get client => synthesize;

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
    abort?.throwIfCancelled();
    calls.add((
      model: model,
      voice: voice,
      input: input,
      responseFormat: responseFormat,
      wavResponseFormat: wavResponseFormat,
      settings: Map.unmodifiable(settings),
      speed: speed,
      language: language,
      instruct: instruct,
      apiKey: apiKey,
    ));
    return GeneratedAudio(
      bytes: bytes,
      sampleRate: sampleRate,
      channels: channels,
    );
  }
}
