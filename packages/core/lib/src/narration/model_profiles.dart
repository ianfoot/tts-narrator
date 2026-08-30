/// Per-model request profiles.
///
/// Every TTS model served by OpenRouter exposes the same `/audio/speech`
/// endpoint and auth, but they differ in the request body, the output format,
/// and how voices work. A [TtsModelProfile] captures the *wiring* needed to
/// build a request for a given model.
///
/// Most profiles are NOT compiled here. Models come from the user's
/// `voice_config.json` (`"models"` block) so the user can point at a
/// different or newer model id (e.g. swap the gemini preview for a GA id)
/// without a rebuild. Only the out-of-box fish bootstrap lives in code, as the
/// app's default until any config overrides it. Voices and pricing are also
/// user data and live in the same config (see `voice_config.dart`).
class TtsModelProfile {
  const TtsModelProfile({
    required this.alias,
    required this.id,
    this.format = 'mp3',
    this.promptStyle = false,
    this.sendsVoiceField = true,
    this.sampleRate,
    this.provider = 'openrouter',
  });

  /// Short CLI name used for `--model <alias>`.
  final String alias;

  /// Full model identifier sent in the request body.
  final String id;

  /// Output encoding: `'pcm'` (wrapped in a WAV header) or `'mp3'` (raw).
  final String format;

  /// Whether accent/style/[calm] directives are woven into the input text.
  /// Gemini understands these; models like Kokoro would read them aloud.
  final bool promptStyle;

  /// Whether to include a `voice` field in the request body.
  final bool sendsVoiceField;

  /// PCM sample rate used for the WAV header and duration; null for MP3.
  final int? sampleRate;

  /// Provider id that serves this model. Filled from the config `"models"`
  /// entry, else `default_provider`, else this compiled fallback so cold start
  /// works — a default value, not special provider treatment.
  final String provider;

  TtsModelProfile copyWith({
    String? id,
    String? provider,
  }) =>
      TtsModelProfile(
        alias: alias,
        id: id ?? this.id,
        format: format,
        promptStyle: promptStyle,
        sendsVoiceField: sendsVoiceField,
        sampleRate: sampleRate,
        provider: provider ?? this.provider,
      );
}

/// The app's out-of-the-box default: the fish model + its free default voice,
/// so first runs cost nothing and the CLI/GUI preselect it before any config
/// exists. The config's `"models"`/`"voices"` blocks can override and extend
/// this; all other models come from the config.
const kDefaultProfile = DefaultProfile(
  profile: TtsModelProfile(
    alias: 'fish',
    id: 'fish-audio/s2.1-pro-free',
    format: 'mp3',
    sendsVoiceField: true,
  ),
  voice: '89f41ea230034706881f85a8227d6ab9',
  voiceLabel: 'British Female Narrator',
);

/// A single default model + voice to preselect on cold start.
class DefaultProfile {
  const DefaultProfile({
    required this.profile,
    required this.voice,
    required this.voiceLabel,
  });

  final TtsModelProfile profile;
  final String voice;
  final String voiceLabel;
}