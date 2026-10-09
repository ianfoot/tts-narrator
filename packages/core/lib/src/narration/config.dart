import 'audio_format.dart';
import 'cost.dart';
import 'model_profiles.dart';
import 'prompt_strings.dart';

/// Configuration for a single narration run.
class NarrationConfig {
  NarrationConfig({
    required this.inputPath,
    this.sourceText,
    required this.profile,
    required this.outputFormat,
    required this.voice,
    this.voiceLabel,
    this.language,
    this.accent = PromptDefaults.accent,
    this.style = PromptDefaults.style,
    this.passagePrefix = PromptDefaults.passagePrefix,
    this.instruct,
    this.minWords = PromptDefaults.minWords,
    this.sendWholeFile = false,
    this.sampleLen,
    this.speed = 1.0,
    this.outDir = 'output',
    this.nestOutputInInputSubdir = true,
    this.dryRun = false,
    this.resume = false,
    this.pricing = freePricing,
    this.providerSettings = const {},
    this.apiKey,
  });

  /// Path to the source text to narrate (required, no default).
  ///
  /// [sourceText] overrides reading from disk: when set, [inputPath] drives only
  /// output naming, and narration uses the in-memory text. This lets the GUI
  /// narrate typed or pasted text with no backing file.
  final String inputPath;

  /// In-memory text to narrate instead of reading [inputPath] from disk.
  ///
  /// Null when the caller has no backing file and expects [inputPath] to be read
  /// from disk.
  final String? sourceText;

  /// TTS model profile driving the request body and prompt.
  final TtsModelProfile profile;

  /// Encoding this run writes, which must be one the model can actually
  /// produce (`profile.supportsFormat`).
  ///
  /// Required rather than defaulted to the model's preference because the caller
  /// knows the user's choice: the GUI remembers a per-model selection and passes
  /// it in. Core deliberately does not clamp it — an unsupported format is a
  /// caller bug, and the resulting provider error says so more clearly than a
  /// silent fallback would.
  ///
  /// This is also the wire format, since every supported format is a container
  /// the provider writes itself.
  final TtsAudioFormat outputFormat;

  /// Model-specific voice name or id.
  final String voice;

  /// Human-readable label for [voice]: the friendly alias when one was used,
  /// otherwise the raw id. Used for display (banner) and the manifest.
  final String? voiceLabel;

  /// Language code for the selected voice (Kokoro: `b`, `j`, ...), or null for
  /// a model that does not take one.
  ///
  /// Read off the voice id's first character by the GUI (see
  /// `VoiceConfig.languageFor`), so it always agrees with [voice]; the model
  /// profile decides whether it is sent at all.
  final String? language;

  /// Free-text accent description used in the prompt.
  final String accent;

  /// Free-text style/register description used in the prompt.
  final String style;

  /// Whether to prepend a `[calm]` style tag to the prompt (merged into
  /// [passagePrefix] — add `[calm] ` to the prefix text if needed).
  /// @deprecated Use [passagePrefix] with `[calm] ` instead.
  @Deprecated('Use passagePrefix with [calm] prefix')
  bool get useCalmTag => false;

  /// Pooled preamble applied to every paragraph prompt.
  final String passagePrefix;

  /// Natural-language description of the voice to synthesize, sent as the
  /// `instruct` field for a model whose profile declares
  /// [TtsModelProfile.sendsInstructField]; null for every other model.
  ///
  /// Unlike [accent] and [style] — which are directives woven *into the spoken
  /// text* for prompt-style models — this describes the narrator and never
  /// reaches the audio as words. Qwen3 Voice Design reads it: that model has no
  /// voice list, so prose is the only way to choose a voice.
  final String? instruct;

  /// If set, only narrate this many paragraphs (smoke test).
  final int? sampleLen;

  /// Speech rate multiplier passed to providers that support it (1.0 = normal).
  final double speed;

  /// Merge a paragraph into the next one when it has fewer than this many
  /// words, so tiny fragments don't get an isolated (off-register) reading.
  final int minWords;

  /// When true, bypass paragraph segmentation and narrate the whole source as
  /// a single TTS call. [minWords] is ignored.
  final bool sendWholeFile;

  /// Output directory for generated WAV files and the manifest.
  final String outDir;

  /// Whether a run writes into `<outDir>/<input-stem>/` instead of `outDir`
  /// itself (see [outputDirPath]).
  ///
  /// True for a run with a real backing file, so several documents narrated into
  /// one chosen folder do not collide. False for an in-memory document: there is
  /// no filename to name a folder after, so files land directly in `outDir`.
  final bool nestOutputInInputSubdir;

  /// If true, print the narration plan and exit without calling the API.
  final bool dryRun;

  /// If true, skip segments already produced in a compatible existing manifest
  /// (matching index + prompt) and keep their records.
  final bool resume;

  /// Cost data (from the voice config) used for the dry-run/estimate.
  final AudioPricing pricing;

  /// Resolved provider settings for the run's provider (see `resolveSettings`).
  ///
  /// Deliberately carries **no credential**: `api_key` is stripped out before
  /// expansion and delivered as [apiKey], so a secret never sits in this map
  /// where it could be logged, serialised, or shown in a diagnostics dump.
  final Map<String, String> providerSettings;

  /// Bearer token for this run, or null when none is configured.
  ///
  /// Null is normal and never an error: the request then carries no
  /// `Authorization` header, and whether one was needed is the server's call (see
  /// `resolveProviderApiKey`). The GUI resolves this from the secure store, the
  /// config block, or the environment; core just forwards it.
  final String? apiKey;

  /// Copy of this config with [inputPath] replaced (used to narrate each file
  /// in a batch directory through the same single-file pipeline).
  NarrationConfig copyWith({required String inputPath}) => NarrationConfig(
    inputPath: inputPath,
    sourceText: sourceText,
    profile: profile,
    outputFormat: outputFormat,
    voice: voice,
    voiceLabel: voiceLabel,
    language: language,
    accent: accent,
    style: style,
    passagePrefix: passagePrefix,
    instruct: instruct,
    minWords: minWords,
    sendWholeFile: sendWholeFile,
    sampleLen: sampleLen,
    speed: speed,
    outDir: outDir,
    nestOutputInInputSubdir: nestOutputInInputSubdir,
    dryRun: dryRun,
    resume: resume,
    pricing: pricing,
    providerSettings: providerSettings,
    apiKey: apiKey,
  );
}
