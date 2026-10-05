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
    this.sendsInstructField = false,
    this.sampleRate,
    required this.provider,
    this.displayName,
    this.defaultInstruct,
    this.voicesEditable = false,
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

  /// Whether the model accepts an `instruct` field in the request body.
  ///
  /// Qwen3 Voice Design has no voice list at all: it *writes* the voice from a
  /// natural-language description — persona and demographics, pitch and timbre,
  /// pace, emotional tone, accent. That prose travels in `instruct`, a field no
  /// other model on the protocol defines, so it is opt-in per model
  /// (`"sends_instruct": true`) exactly like [supportsSpeed].
  ///
  /// Mutually exclusive in practice with [sendsVoiceField]: a voice-design model
  /// is described, not selected.
  final bool sendsInstructField;

  /// PCM sample rate used for the WAV header and duration; null for MP3.
  final int? sampleRate;

  /// Name of the `providers.<name>` block that serves this model. Required in
  /// the model config file, and opaque to core: it is a lookup key into user
  /// config, never a vendor the code knows about.
  final String provider;

  /// The `instruct` prose a [sendsInstructField] model starts from, if the model
  /// file supplies one.
  ///
  /// Voice design has no "unset" state to fall back to — the model is described
  /// or it is not, so a shipped model that declares `sends_instruct` should say
  /// something here. Carrying it on the profile (rather than only in the model
  /// file) is what lets the GUI prefill an editable control without core knowing
  /// anything about the GUI's defaults.
  final String? defaultInstruct;

  /// Whether the user may edit this model's voice list from the app.
  ///
  /// Some models have a closed set of voices the provider itself defines
  /// (Gemini's 30 named voices, Kokoro's 54 language-prefixed ids). Others are
  /// open-ended: Fish accepts any id, so the useful thing is for the user to
  /// curate their own list. That is opt-in per model
  /// (`"voices_editable": true` in the model file) and defaults to false, so a
  /// model that says nothing is read-only in the UI.
  ///
  /// This gates the *UI affordance* only. The capability is always there: a
  /// hand-written overlay file can change any model's voices, and the loader
  /// honours it regardless of this flag.
  final bool voicesEditable;

  TtsModelProfile copyWith({String? id, String? provider}) => TtsModelProfile(
    alias: alias,
    id: id ?? this.id,
    format: format,
    promptStyle: promptStyle,
    sendsVoiceField: sendsVoiceField,
    supportsSpeed: supportsSpeed,
    sendsLanguageField: sendsLanguageField,
    sendsInstructField: sendsInstructField,
    sampleRate: sampleRate,
    provider: provider ?? this.provider,
    displayName: displayName,
    defaultInstruct: defaultInstruct,
    voicesEditable: voicesEditable,
  );
}
