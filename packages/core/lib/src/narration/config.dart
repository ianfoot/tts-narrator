import 'cost.dart';
import 'model_profiles.dart';
import 'prompt_strings.dart';

/// Configuration for a single narration run.
class NarrationConfig {
  NarrationConfig({
    required this.inputPath,
    this.sourceText,
    required this.profile,
    required this.voice,
    this.voiceLabel,
    this.language,
    this.accent = PromptDefaults.accent,
    this.style = PromptDefaults.style,
    this.passagePrefix = PromptDefaults.passagePrefix,
    this.minWords = PromptDefaults.minWords,
    this.sendWholeFile = false,
    this.sampleLen,
    this.speed = 1.0,
    this.outDir = 'output',
    this.dryRun = false,
    this.resume = false,
    this.pricing = freePricing,
    this.providerSettings = const {},
    this.apiKey,
  });

  /// Path to the source text to narrate (required, no default).
  ///
  /// [sourceText] overrides reading from disk: when set, [inputPath] drives
  /// only output naming (stem/out-dir); narration uses the in-memory text.
  /// This lets the GUI narrate typed or pasted text with no backing file.
  final String inputPath;

  /// In-memory text to narrate instead of reading [inputPath] from disk.
  ///
  /// When null (the CLI), [inputPath] is read as before. The CLI never sets
  /// this; the GUI sets it for typed/pasted content.
  final String? sourceText;

  /// TTS model profile driving the request body, prompt, and output format.
  final TtsModelProfile profile;

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

  /// If true, print the narration plan and exit without calling the API.
  final bool dryRun;

  /// If true, skip segments already produced in a compatible existing manifest
  /// (matching index + fingerprint) and keep their records.
  final bool resume;

  /// Cost data (from the voice config) used for the dry-run/estimate.
  final AudioPricing pricing;

  /// Resolved provider settings for the run's provider (see `resolveSettings`).
  /// Built once when the config is assembled; providers read their non-secret
  /// settings from here.
  ///
  /// Deliberately carries **no credential**: `api_key` is stripped out before
  /// expansion and delivered as [apiKey], so a secret never sits in this map
  /// where it could be logged, serialised, or shown in a diagnostics dump.
  final Map<String, String> providerSettings;

  /// Bearer token for this run, or null when none is configured.
  ///
  /// Null is normal and is never an error: it means the request carries no
  /// `Authorization` header, and whether the server requires one is the
  /// server's decision. The GUI resolves this from the secure store, the config
  /// block, or the environment; core just forwards it.
  final String? apiKey;

  /// Copy of this config with [inputPath] replaced (used to narrate each file
  /// in a batch directory through the same single-file pipeline).
  NarrationConfig copyWith({required String inputPath}) => NarrationConfig(
    inputPath: inputPath,
    sourceText: sourceText,
    profile: profile,
    voice: voice,
    voiceLabel: voiceLabel,
    language: language,
    accent: accent,
    style: style,
    passagePrefix: passagePrefix,
    minWords: minWords,
    sendWholeFile: sendWholeFile,
    sampleLen: sampleLen,
    speed: speed,
    outDir: outDir,
    dryRun: dryRun,
    resume: resume,
    pricing: pricing,
    providerSettings: providerSettings,
    apiKey: apiKey,
  );
}
