import 'package:flutter/widgets.dart';

/// Platform-neutral determinate progress bar (Cupertino has no built-in one in
/// this SDK): a thin track with a rounded fill sized to [value].
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    required this.valueColor,
    required this.backgroundColor,
    this.minHeight = 4,
  });

  /// Fill fraction from 0.0 to 1.0 (clamped).
  final double value;
  final Color valueColor;
  final Color backgroundColor;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    return Container(
      height: minHeight,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(minHeight / 2),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: clamped,
          child: Container(
            decoration: BoxDecoration(
              color: valueColor,
              borderRadius: BorderRadius.circular(minHeight / 2),
            ),
          ),
        ),
      ),
    );
  }
}
