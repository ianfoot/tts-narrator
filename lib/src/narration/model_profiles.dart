/// Per-model notification profiles.
///
/// Every TTS model served by OpenRouter exposes the same `/audio/speech`
/// endpoint and auth, but they differ in the request body, the voice
/// identifiers, and the output format. This table captures those differences
/// so the pipeline can stay model-agnostic.
class TtsModelProfile {
  const TtsModelProfile({
    required this.alias,
    required this.id,
    required this.defaultVoice,
    required this.voices,
    required this.promptStyle,
    required this.format,
    this.voiceFreeForm = false,
    this.sendsVoiceField = true,
    this.sampleRate,
  });

  /// Short CLI name used for `--model <alias>`.
  final String alias;

  /// Full model identifier sent in the request body.
  final String id;

  /// Default voice when `--voice` is omitted.
  final String defaultVoice;

  /// Known voices for this model. Used to validate `--voice` unless
  /// [voiceFreeForm] is true.
  final List<String> voices;

  /// When false, the accepted list is not authoritative: `--voice` is a raw
  /// provider-specific identifier and is passed through unvalidated.
  final bool voiceFreeForm;

  /// Whether to include a `voice` field in the request body.
  final bool sendsVoiceField;

  /// Whether accent/style/[calm] directives are woven into the input text.
  /// Gemini understands these; models like Kokoro would read them aloud.
  final bool promptStyle;

  /// Output encoding: `'pcm'` (wrapped in a WAV header) or `'mp3'` (raw).
  final String format;

  /// PCM sample rate used for the WAV header and duration; null for MP3.
  final int? sampleRate;
}

/// Gemini 3.1 Flash TTS Preview: prompt-driven styling, named voices, 24 kHz
/// mono 16-bit PCM.
const kGeminiProfile = TtsModelProfile(
  alias: 'gemini',
  id: 'google/gemini-3.1-flash-tts-preview',
  defaultVoice: 'Charon',
  voices: [
    'Zephyr', 'Puck', 'Charon', 'Kore', 'Fenrir', 'Leda', 'Orus', 'Aoede',
    'Callirrhoe', 'Autonoe', 'Enceladus', 'Iapetus', 'Umbriel', 'Algieba',
    'Despina', 'Erinome', 'Algenib', 'Rasalgethi', 'Laomedeia', 'Achernar',
    'Alnilam', 'Schedar', 'Gacrux', 'Pulcherrima', 'Achird', 'Zubenelgenubi',
    'Vindemiatrix', 'Sadachbia', 'Sadaltager', 'Sulafat',
  ],
  promptStyle: true,
  format: 'pcm',
  sampleRate: 24000,
);

/// Kokoro 82M (hexgrad/kokoro-82m): provider-specific voice ids, no prompt
/// styling, MP3 output (defaults to pcm on the wire, but we always request
/// mp3 for playable files).
const kKokoroProfile = TtsModelProfile(
  alias: 'kokoro',
  id: 'hexgrad/kokoro-82m',
  defaultVoice: 'bf_emma',
  voices: [
    'bf_alice', 'bf_emma', 'bf_isabella', 'bf_lily',
    'bm_daniel', 'bm_fable', 'bm_george', 'bm_lewis',
  ],
  voiceFreeForm: true,
  promptStyle: false,
  format: 'mp3',
  sampleRate: 24000,
);

/// Fish Audio S2.1 Pro (free) (fish-audio/s2.1-pro-free): free model routed
/// by OpenRouter. Voices are 32-hex fish.audio ids (curated British list lives
/// on the "Text to Speech" Logseq page). No prompt styling — inline brackets
/// read aloud. MP3 output. Transient 502s are not billed.
const kFishProfile = TtsModelProfile(
  alias: 'fish',
  id: 'fish-audio/s2.1-pro-free',
  defaultVoice: '89f41ea230034706881f85a8227d6ab9',
  voices: [],
  voiceFreeForm: true,
  sendsVoiceField: true,
  promptStyle: false,
  format: 'mp3',
);

/// All known model profiles, keyed by [TtsModelProfile.alias].
final kModelProfiles = <String, TtsModelProfile>{
  for (final p in [kGeminiProfile, kKokoroProfile, kFishProfile])
    p.alias: p,
};

/// Resolves a `--model` value by alias or full id, or null if unknown.
TtsModelProfile? profileFor(String aliasOrId) {
  final direct = kModelProfiles[aliasOrId];
  if (direct != null) return direct;
  for (final p in kModelProfiles.values) {
    if (p.id == aliasOrId) return p;
  }
  return null;
}