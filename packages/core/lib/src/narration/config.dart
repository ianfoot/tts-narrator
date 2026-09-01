import 'cost.dart';
import 'model_profiles.dart';

/// Configuration for a single narration run.
class NarrationConfig {
  NarrationConfig({
    required this.inputPath,
    this.sourceText,
    required this.profile,
    required this.voice,
    this.voiceLabel,
    this.accent = 'southern British English, neutral and clear',
    this.style = 'warm, composed, restrained, literary',
    this.useCalmTag = false,
    this.passagePrefix =
        'Narrate this passage for an audiobook. You are a warm, composed female narrator.',
    this.minWords = 30,
    this.sampleLen,
    this.outDir = 'output',
    this.dryRun = false,
    this.resume = false,
    this.pricing = freePricing,
    this.providerSettings = const {},
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

  /// Free-text accent description used in the prompt.
  final String accent;

  /// Free-text style/register description used in the prompt.
  final String style;

  /// Whether to prepend a `[calm]` style tag to the prompt.
  final bool useCalmTag;

  /// Pooled preamble applied to every paragraph prompt.
  final String passagePrefix;

  /// If set, only narrate this many paragraphs (smoke test).
  final int? sampleLen;

  /// Merge a paragraph into the next one when it has fewer than this many
  /// words, so tiny fragments don't get an isolated (off-register) reading.
  final int minWords;

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
  /// Built once when the config is assembled; providers read their secrets
  /// from here, never from the environment per segment.
  final Map<String, String> providerSettings;

  /// Copy of this config with [inputPath] replaced (used to narrate each file
  /// in a batch directory through the same single-file pipeline).
  NarrationConfig copyWith({required String inputPath}) => NarrationConfig(
        inputPath: inputPath,
        sourceText: sourceText,
        profile: profile,
        voice: voice,
        voiceLabel: voiceLabel,
        accent: accent,
        style: style,
        useCalmTag: useCalmTag,
        passagePrefix: passagePrefix,
        minWords: minWords,
        sampleLen: sampleLen,
        outDir: outDir,
        dryRun: dryRun,
        resume: resume,
        pricing: pricing,
        providerSettings: providerSettings,
      );
}