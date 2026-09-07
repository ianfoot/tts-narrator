import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Platform-aware switch: [CupertinoSwitch] on macOS, [Switch] elsewhere.
class PlatformSwitch extends StatelessWidget {
  const PlatformSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value when toggled; null disables the switch.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => Transform.scale(
        scale: AppMetrics.controlKnobScale,
        child: CupertinoSwitch(value: value, onChanged: onChanged),
      ),
      TargetPlatform.windows ||
      TargetPlatform.linux => Switch(value: value, onChanged: onChanged),
      _ => throw UnimplementedError(),
    };
  }
}
