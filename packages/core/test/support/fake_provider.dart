import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Records every [synthesize] call and returns configurable bytes, so tests can
/// assert what `narrate` dispatches to the provider without any network.
class FakeTtsProvider implements TtsProvider {
  FakeTtsProvider({List<int>? bytes}) : bytes = bytes ?? 'fake-audio'.codeUnits;

  /// Bytes returned by [synthesize].
  final List<int> bytes;

  final List<
    ({
      String model,
      String? voice,
      String input,
      String responseFormat,
      Map<String, String> settings,
    })
  >
  calls = [];

  int get callCount => calls.length;

  @override
  String get id => 'fake';

  @override
  String get name => 'Fake TTS';

  @override
  Future<ProviderAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
    AbortToken? abort,
  }) async {
    abort?.throwIfCancelled();
    calls.add((
      model: model,
      voice: voice,
      input: input,
      responseFormat: responseFormat,
      settings: Map.unmodifiable(settings),
    ));
    return ProviderAudio(bytes: bytes);
  }
}
