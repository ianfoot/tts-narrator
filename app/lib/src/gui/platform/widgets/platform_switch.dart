import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Platform-aware switch: [CupertinoSwitch] on macOS, [Switch] elsewhere.
class PlatformSwitch extends StatelessWidget {
  const PlatformSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.tooltip,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value when toggled; null disables the switch.
  final ValueChanged<bool>? onChanged;

  /// Hover text shown when the mouse sits on the switch.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget switchWidget;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      switchWidget = Transform.scale(
        scale: AppMetrics.controlKnobScale,
        child: CupertinoSwitch(value: value, onChanged: onChanged),
      );
    } else {
      switchWidget = Switch(value: value, onChanged: onChanged);
    }
    return tooltip == null ? switchWidget : Localizations.override(
      context: context,
      delegates: const [DefaultMaterialLocalizations.delegate],
      child: Tooltip(message: tooltip!, child: switchWidget),
    );
  }
}
