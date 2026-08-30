import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Visual weighting for [PlatformButton].
enum PlatformButtonStyle { filled, outlined }

/// Platform-aware button: Cupertino on macOS, Material everywhere else.
class PlatformButton extends StatelessWidget {
  const PlatformButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.style = PlatformButtonStyle.filled,
  });

  /// Tap handler; null disables the button.
  final VoidCallback? onPressed;

  /// Button label.
  final Widget child;

  /// Optional leading icon (rendered inline on Cupertino, as `.icon` on
  /// Material).
  final Widget? icon;

  final PlatformButtonStyle style;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _buildCupertino();
    }
    return _buildMaterial();
  }

  Widget _buildCupertino() {
    final label = icon == null
        ? child
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon!,
              const SizedBox(width: 6),
              child,
            ],
          );
    if (style == PlatformButtonStyle.outlined) {
      return CupertinoButton(
        onPressed: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: CupertinoColors.systemGrey,
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: label,
        ),
      );
    }
    return CupertinoButton.filled(onPressed: onPressed, child: label);
  }

  Widget _buildMaterial() {
    if (style == PlatformButtonStyle.outlined) {
      return OutlinedButton.icon(onPressed: onPressed, icon: icon ?? const SizedBox.shrink(), label: child);
    }
    return FilledButton.icon(onPressed: onPressed, icon: icon ?? const SizedBox.shrink(), label: child);
  }
}