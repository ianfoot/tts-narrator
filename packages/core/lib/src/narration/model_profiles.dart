/// Per-model request profiles.
///
/// Every TTS model served by an OpenAI-compatible provider exposes the same
/// `/audio/speech` endpoint and auth, but they differ in the request body, the
/// output format, and how voices work. A [TtsModelProfile] captures the *wiring*
/// needed to build a request for a given model.
///
/// Models are never compiled here: they come only from the user's config
/// directory (`<alias>.json`), so the user can point at a different or newer
/// model id (e.g. swap the gemini preview for a GA id) without a rebuild.
/// Voices and pricing are also user data and live in the per-model files (see
/// `voice_config.dart`).
class TtsModelProfile {
  const TtsModelProfile({
    required this.alias,
    required this.id,
    this.format = 'mp3',
    this.promptStyle = false,
    this.sendsVoiceField = true,
    this.supportsSpeed = false,
    this.sendsLanguageField = false,
    this.sampleRate,
    required this.provider,
    this.displayName,
  });

  /// Short CLI name used for `--model <alias>`.
  final String alias;

  /// Full model identifier sent in the request body.
  final String id;

  /// Optional friendly name for the GUI dropdown (e.g. "Fish Audio S2.1
  /// (Free)"). Null falls back to the `alias — id` pairing in UI labels.
  final String? displayName;

  /// Output encoding: `'pcm'` (wrapped in a WAV header) or `'mp3'` (raw).
  final String format;

  /// Whether accent/style/[calm] directives are woven into the input text.
  /// Gemini understands these; models like Kokoro would read them aloud.
  final bool promptStyle;

  /// Whether to include a `voice` field in the request body.
  final bool sendsVoiceField;

  /// Whether the model accepts a `speed` multiplier in the request body.
  ///
  /// The OpenAI speech protocol defines the field but not every vendor honours
  /// it, so it is opt-in per model (`"speed": true` in the model file). When
  /// false the field is omitted from the request entirely rather than sent at a
  /// default, and the GUI hides the speed slider.
  final bool supportsSpeed;

  /// Whether the model accepts a `lang_code` field in the request body.
  ///
  /// Kokoro ships one multi-language voice set, where the language is named by
  /// the voice id's first character and the API also takes it as an explicit
  /// `lang_code`. It is opt-in per model (`"sends_language": true`) for the same
  /// reason as [supportsSpeed]: the field only exists on some vendors, and is
  /// omitted entirely otherwise.
  final bool sendsLanguageField;

  /// PCM sample rate used for the WAV header and duration; null for MP3.
  final int? sampleRate;

  /// Name of the `providers.<name>` block that serves this model. Required in
  /// the model config file, and opaque to core: it is a lookup key into user
  /// config, never a vendor the code knows about.
  final String provider;

  TtsModelProfile copyWith({String? id, String? provider}) => TtsModelProfile(
    alias: alias,
    id: id ?? this.id,
    format: format,
    promptStyle: promptStyle,
    sendsVoiceField: sendsVoiceField,
    supportsSpeed: supportsSpeed,
    sendsLanguageField: sendsLanguageField,
    sampleRate: sampleRate,
    provider: provider ?? this.provider,
    displayName: displayName,
  );
}
