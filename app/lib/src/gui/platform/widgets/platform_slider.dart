import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Platform-aware slider: [CupertinoSlider] on macOS, [Slider] elsewhere.
class PlatformSlider extends StatelessWidget {
  const PlatformSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.label,
  });

  /// Current selected value (must be within [min]..[max]).
  final double value;

  /// Called with the new value when the user drags the slider.
  final ValueChanged<double> onChanged;

  final double min;
  final double max;

  /// Number of discrete divisions (null = continuous).
  final int? divisions;

  /// Optional label (rendered below the slider on Material).
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return Transform.scale(
        alignment: Alignment.centerLeft,
        scale: AppMetrics.controlKnobScale,
        child: CupertinoSlider(
          value: value,
          onChanged: onChanged,
          min: min,
          max: max,
          divisions: divisions,
        ),
      );
    }
    return Slider(
      value: value,
      onChanged: onChanged,
      min: min,
      max: max,
      divisions: divisions,
      label: label,
    );
  }
}
