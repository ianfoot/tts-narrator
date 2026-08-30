import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Simplest fake provider: registers under the `openrouter` id so narration
/// runs without the real network dependency. Returns each [synthesize] result
/// with the configured bytes and records every call.
class FakeTtsProvider implements TtsProvider {
  FakeTtsProvider({List<int>? bytes}) : bytes = bytes ?? 'fake-audio'.codeUnits;

  /// Bytes returned by [synthesize].
  final List<int> bytes;

  final List<
    ({String model, String? voice, String input, String responseFormat})
  >
  calls = [];

  int get callCount => calls.length;

  @override
  String get id => 'openrouter';

  @override
  String get name => 'Fake TTS';

  /// Model UI spec to surface for the given model (declarable per test).
  ModelUiSpec modelUiSpec = const ModelUiSpec.empty();

  /// Optional per-alias specs overriding [modelUiSpec]; keyed by model alias.
  final Map<String, ModelUiSpec> specsByAlias = {};

  @override
  ModelUiSpec modelUiSpecFor(TtsModelProfile model) =>
      specsByAlias[model.alias] ?? modelUiSpec;

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
    ));
    return ProviderAudio(bytes: bytes);
  }

  /// Registers this instance with the shared registry under `openrouter`
  /// (like `main.dart` does), so `narrate` finds it without real credentials.
  void register() => ttsProviderRegistry.register('openrouter', () => this);
}