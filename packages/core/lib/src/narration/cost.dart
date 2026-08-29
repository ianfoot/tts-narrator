import 'model_profiles.dart';

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

/// Estimated USD cost of narrating [chunks] with [profile], using OpenRouter
/// pricing from the profile. Approximate — assumes ~4 text tokens per word's
/// chars for token-billed input and the nominal narration pace for
/// duration-billed output (Gemini). Free models (e.g. fish) return 0.
double estimateCostUsd(TtsModelProfile profile, List<String> chunks) {
  final pricing = profile.pricing;
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