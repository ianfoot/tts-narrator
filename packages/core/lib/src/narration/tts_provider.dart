import 'abort.dart';
import 'model_profiles.dart';
import 'model_ui.dart';

/// A synthesized audio sample from a TTS provider.
class GeneratedAudio {
  GeneratedAudio({required this.bytes, this.generationId});

  /// Raw audio bytes in the provider's requested [format].
  final List<int> bytes;

  /// Optional provider-specific generation/correlation metadata. The OpenRouter
  /// provider maps its `X-Generation-Id` response header onto this inside its
  /// own package; it is generic, optional metadata here and is not yet wired
  /// into the manifest.
  final String? generationId;
}

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
  /// `accent`/`style`/`passagePrefix`/`useCalmTag` convention. The plugin
  /// receives the full [TtsModelProfile] so it can key its UI off request
  /// shape (id, prompt styling) rather than the user-editable alias.
  ModelUiSpec modelUiSpecFor(TtsModelProfile model) =>
      const ModelUiSpec.empty();

  /// Synthesizes [input] as audio in [responseFormat], optionally choosing a
  /// [voice], returning the raw bytes.
  ///
  /// [settings] is the run's resolved provider settings map (see
  /// [resolveSettings]); [abort] is checked between retries (and before the
  /// first attempt) — an already-cancelled token throws [AbortException]
  /// without calling the API.
  Future<GeneratedAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
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

/// Matches a `${ENV_NAME}` secret reference in a provider settings value.
final _envRef = RegExp(r'^\$\{(\w+)\}$');

/// Resolves a provider's raw settings map, applying the generic secret rule.
///
/// A value matching `^\$\{(\w+)\}$` reads that environment variable (from [env],
/// defaulting to an empty map) at resolution time — once when the run config is
/// built, never per segment. Any other value passes through literal (so `api_key`
/// literals and already-resolved values survive untouched).
///
/// Throws a [StateError] naming the variable when the referenced env var is
/// missing or empty (an empty value counts as missing, matching the legacy
/// `resolvedApiKey` behaviour); remaining environment access is the caller's
/// job, so core stays provider-agnostic.
Map<String, String> resolveSettings(
  Map<String, String> raw, {
  Map<String, String>? env,
}) {
  final envMap = env ?? const <String, String>{};
  final out = <String, String>{};
  for (final MapEntry(:key, :value) in raw.entries) {
    final match = _envRef.firstMatch(value);
    if (match == null) {
      out[key] = value;
      continue;
    }
    final name = match.group(1)!;
    final resolved = envMap[name];
    if (resolved == null || resolved.trim().isEmpty) {
      throw StateError(
        'Missing environment variable "$name" referenced by provider '
        'setting "$key".',
      );
    }
    out[key] = resolved;
  }
  return out;
}
