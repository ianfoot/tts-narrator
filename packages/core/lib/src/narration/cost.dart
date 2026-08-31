/// Cost data used for the `--dry-run` estimate and the GUI's summary card.
///
/// Pricing is per-model data from each model's OpenRouter page, so it lives in
/// the user's per-model config files (`pricing` in `models/<alias>.json`)
/// rather than in code — it can drift or be edited without a rebuild. Any
/// model without pricing entry is treated as free (estimate prints 0).
class AudioPricing {
  const AudioPricing({
    this.inputUsdPerMTokens,
    this.outputUsdPerMTokens,
    this.usdPerMChars,
  });

  /// USD per 1M input tokens (text tokens — e.g. Gemini).
  final double? inputUsdPerMTokens;

  /// USD per 1M output audio tokens (Gemini bills audio output by token).
  final double? outputUsdPerMTokens;

  /// USD per 1M input characters (Kokoro bills by character).
  final double? usdPerMChars;

  bool get isFree =>
      (inputUsdPerMTokens ?? 0) == 0 &&
      (outputUsdPerMTokens ?? 0) == 0 &&
      (usdPerMChars ?? 0) == 0;

  @override
  bool operator ==(Object other) =>
      other is AudioPricing &&
      other.inputUsdPerMTokens == inputUsdPerMTokens &&
      other.outputUsdPerMTokens == outputUsdPerMTokens &&
      other.usdPerMChars == usdPerMChars;

  @override
  int get hashCode =>
      Object.hash(inputUsdPerMTokens, outputUsdPerMTokens, usdPerMChars);
}

/// Default pricing: free (used when a model has no `pricing` in the config).
const freePricing = AudioPricing();

/// Words per minute assumed for narration-duration estimation.
const _narrationWordsPerMinute = 160.0;

/// Gemini bills audio output per token; standard mapping for Gemini TTS.
const _geminiTokensPerSecond = 160.0;

/// Estimated narration duration in minutes for [chunks], based on a nominal
/// narration pace (words / 160 wpm). Used for the dry-run estimate and the
/// run banner.
double estimateMinutes(List<String> chunks) {
  var words = 0;
  for (final c in chunks) {
    words += c.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }
  return words / _narrationWordsPerMinute;
}

/// Estimated USD cost of narrating [chunks] with [pricing], using the pricing
/// from the voice config. Approximate — assumes ~4 text tokens per word's
/// chars for token-billed input and the nominal narration pace for
/// duration-billed output (Gemini). Free models (e.g. fish) return 0.
double estimateCostUsd(AudioPricing pricing, List<String> chunks) {
  if (pricing.isFree) return 0;

  var chars = 0;
  for (final c in chunks) {
    chars += c.length;
  }

  if (pricing.usdPerMChars != null) {
    return chars / 1e6 * pricing.usdPerMChars!;
  }

  final textTokens = (chars / 4).ceil();
  final inputCost = textTokens / 1e6 * (pricing.inputUsdPerMTokens ?? 0);
  final estSeconds = estimateMinutes(chunks) * 60;
  final outputCost = estSeconds * _geminiTokensPerSecond / 1e6 *
      (pricing.outputUsdPerMTokens ?? 0);
  return inputCost + outputCost;
}

/// Short, human-friendly currency string (e.g. "$0.00", "$2.41"). Free
/// models read "$0.00 (free)".
String formatCostUsd(double usd) =>
    usd == 0 ? r'$0.00 (free)' : '\$${usd.toStringAsFixed(2)}';