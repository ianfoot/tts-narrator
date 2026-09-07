import 'package:flutter/widgets.dart';

/// Platform-neutral determinate progress bar (Cupertino has no built-in
/// determinate bar in this SDK). A thin track with a rounded fill sized to
/// [value]; has no Material dependency, so it is safe under Cupertino too.
class PlatformProgressBar extends StatelessWidget {
  const PlatformProgressBar({
    super.key,
    required this.value,
    required this.valueColor,
    required this.backgroundColor,
    this.minHeight = 4,
  });

  /// Progress from 0.0 to 1.0.
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
