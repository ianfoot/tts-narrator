import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Visual weighting for [PlatformButton].
enum PlatformButtonStyle { filled, outlined }

/// Platform-aware button: Cupertino on macOS, Material elsewhere.
///
/// The filled style is a custom accent-primary container rather than
/// `CupertinoButton.filled`, whose SDK-default geometry is taller than the
/// app's 44px toolbar and clipped the toolbar Narrate button. The child is
/// styled white through a `DefaultTextStyle` so a filled button renders white
/// text/icons without every caller specifying the color.
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
      return _buildCupertino(context);
    }
    return _buildMaterial();
  }

  Widget _buildCupertino(BuildContext context) {
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
              color: AppTokens.of(context).colors.borderSubtle,
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          ),
          child: label,
        ),
      );
    }
    final accent = AppTokens.of(context).colors.accentPrimary;
    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        // Icons resolve color from IconTheme, not DefaultTextStyle; without
        // this the root Cupertino IconTheme (accent-primary) would make icons
        // invisible on the same-colored fill.
        child: IconTheme(
          data: const IconThemeData(color: Colors.white),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            ),
            child: label,
          ),
        ),
      ),
    );
  }

  Widget _buildMaterial() {
    if (style == PlatformButtonStyle.outlined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon ?? const SizedBox.shrink(),
        label: child,
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: icon ?? const SizedBox.shrink(),
      label: child,
    );
  }
}