import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;

import '../theme/app_tokens.dart';

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.tooltip,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final switchControl = Transform.scale(
      scale: AppMetrics.controlKnobScale,
      child: CupertinoSwitch(value: value, onChanged: onChanged),
    );
    if (tooltip == null) return switchControl;
    return Tooltip(message: tooltip!, child: switchControl);
  }
}
