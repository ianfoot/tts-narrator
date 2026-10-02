import 'abort.dart';
import 'model_profiles.dart';
import 'model_ui.dart';
import 'speech_client.dart';

/// A provider-agnostic text-to-speech backend.
///
/// Core knows nothing concrete about any provider: auth, request bodies,
/// retries, and output wrapping are the provider's job. A provider only needs
/// to turn [input] into audio bytes for [model] (with optional [voice] and
/// [responseFormat]) using its resolved [settings], honoring [abort] between
/// requests/retries.
abstract class TtsProvider {
  /// Stable identifier used in config (`"provider": "<id>"`) and `--provider`.
  String get id;

  /// Human-readable name for banners/UI.
  String get name;

  /// Declares the editable GUI options for [model]; empty by default.
  ///
  /// The provider package is the model's plugin: it decides which controls a
  /// model gets in the GUI and the app renders them generically. Core ships no
  /// model-specific UI knowledge — the keys are the shared
  /// `accent`/`style`/`passagePrefix` convention. The plugin
  /// receives the full [TtsModelProfile] so it can key its UI off request
  /// shape (id, prompt styling) rather than the user-editable alias.
  ModelUiSpec modelUiSpecFor(TtsModelProfile model) =>
      const ModelUiSpec.empty();

  /// Synthesizes [input] as audio in [responseFormat], optionally choosing a
  /// [voice], returning the raw bytes.
  ///
  /// [speed] is a speech-rate multiplier (1.0 = normal); providers that have
  /// no speed concept should ignore it. [settings] is the run's resolved
  /// provider settings map (see `resolveSettings`); [abort] is checked between
  /// retries (and before the first attempt) — an already-cancelled token
  /// throws [AbortException] without calling the API.
  Future<GeneratedAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
    double speed = 1.0,
    AbortToken? abort,
  });
}

/// Registry of provider factories, populated at startup by each entrypoint.
///
/// Core registers nothing — concrete provider packages (e.g. openrouter) are
/// `register()`d by the CLI and GUI before `parseArgs`/`narrate` run. The
/// shared [ttsProviderRegistry] instance is used everywhere so registrations
/// are visible to config parsing and narration dispatch alike.
class TtsProviderRegistry {
  final Map<String, TtsProvider Function()> _factories = {};

  /// Registers [factory] under [id], replacing any previous registration.
  void register(String id, TtsProvider Function() factory) {
    _factories[id] = factory;
  }

  /// Instantiates the provider registered under [id], or null when unknown.
  TtsProvider? resolveOrNull(String id) {
    final factory = _factories[id];
    return factory == null ? null : factory();
  }

  /// Instantiates the provider registered under [id].
  ///
  /// Throws a [StateError] listing the registered ids when [id] is unknown, so
  /// entrypoints can render "unknown provider 'id' — registered: a, b".
  TtsProvider resolve(String id) {
    final provider = resolveOrNull(id);
    if (provider != null) return provider;
    final registered = _factories.keys.toList()..sort();
    throw StateError(
      'Unknown provider "$id". '
      'Registered: ${registered.isEmpty ? '(none)' : registered.join(', ')}.',
    );
  }
}

/// The registry shared by the CLI, GUI, and core narration dispatch.
final TtsProviderRegistry ttsProviderRegistry = TtsProviderRegistry();
