import 'package:flutter/widgets.dart';

import '../theme/app_tokens.dart';

/// Tier 2 field title (e.g. "Model", "Voice alias"): 13pt Medium primary,
/// sitting 4px above its control and 12px below the preceding one.
Widget settingsFieldLabel(AppTokens tokens, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 4, top: 12),
  child: Text(text, style: tokens.typography.body),
);

/// Inline control label (e.g. "Sample mode", "Skip completed segments") —
/// Tier 2: 13pt Medium primary, matching the field titles so toggle labels
/// (previously 14pt/bold) sit at the same visual weight.
Widget settingsControlLabel(AppTokens tokens, String text) =>
    Text(text, style: tokens.typography.body);
