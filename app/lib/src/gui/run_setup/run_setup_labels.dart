import 'package:flutter/widgets.dart';

import '../theme/app_tokens.dart';

/// Tier 2 field title (e.g. "Model", "Voice"): 13pt Medium primary,
/// sitting 4px above its control and 12px below the preceding one.
Widget runSetupFieldLabel(AppTokens tokens, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 4, top: 12),
  child: Text(text, style: tokens.typography.body),
);

/// Inline control label (e.g. "Sample mode", "Skip completed segments") — Tier
/// 2 like the field titles, so toggle labels sit at the same visual weight.
Widget runSetupControlLabel(AppTokens tokens, String text) =>
    Text(text, style: tokens.typography.body);
