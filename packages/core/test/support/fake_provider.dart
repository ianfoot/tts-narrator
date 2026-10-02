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
  FakeTtsProvider({List<int>? bytes}) : bytes = bytes ?? 'fake-audio'.codeUnits;

  /// Provider label recorded on the profile under test, so a profile and this
  /// fake name the same block. Not part of any interface — core no longer
  /// resolves providers — but tests use it to keep the two in step.
  String get id => testProvider;

  /// Bytes returned by [synthesize].
  final List<int> bytes;

  final List<
    ({
      String model,
      String? voice,
      String input,
      String responseFormat,
      Map<String, String> settings,
      double? speed,
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
    required String responseFormat,
    required Map<String, String> settings,
    required double? speed,
    AbortToken? abort,
  }) async {
    abort?.throwIfCancelled();
    calls.add((
      model: model,
      voice: voice,
      input: input,
      responseFormat: responseFormat,
      settings: Map.unmodifiable(settings),
      speed: speed,
    ));
    return GeneratedAudio(bytes: bytes);
  }
}
