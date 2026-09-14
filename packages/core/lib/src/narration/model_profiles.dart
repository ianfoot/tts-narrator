/// Per-model request profiles.
///
/// Every TTS model served by OpenRouter exposes the same `/audio/speech`
/// endpoint and auth, but they differ in the request body, the output format,
/// and how voices work. A [TtsModelProfile] captures the *wiring* needed to
/// build a request for a given model.
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
    this.sampleRate,
    this.provider = 'openrouter',
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

  /// PCM sample rate used for the WAV header and duration; null for MP3.
  final int? sampleRate;

  /// Provider id that serves this model. Required in the model config file.
  final String provider;

  TtsModelProfile copyWith({String? id, String? provider}) => TtsModelProfile(
    alias: alias,
    id: id ?? this.id,
    format: format,
    promptStyle: promptStyle,
    sendsVoiceField: sendsVoiceField,
    sampleRate: sampleRate,
    provider: provider ?? this.provider,
    displayName: displayName,
  );
}