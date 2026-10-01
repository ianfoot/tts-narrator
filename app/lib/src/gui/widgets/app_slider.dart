import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;

class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.tooltip,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int? divisions;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final slider = CupertinoSlider(
      value: value,
      onChanged: onChanged,
      min: min,
      max: max,
      divisions: divisions,
    );
    if (tooltip == null) return slider;
    return Tooltip(message: tooltip!, child: slider);
  }
}
