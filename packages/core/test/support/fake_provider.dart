import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Records every [synthesize] call and returns configurable bytes, so tests can
/// assert what `narrate` dispatches to the client without any network.
class FakeTtsProvider {
  FakeTtsProvider({List<int>? bytes}) : bytes = bytes ?? 'fake-audio'.codeUnits;

  /// Provider label recorded on the profile under test. Not part of any
  /// interface anymore (core no longer resolves providers), but tests use it
  /// to keep profile and fake in step.
  String get id => 'fake';

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
