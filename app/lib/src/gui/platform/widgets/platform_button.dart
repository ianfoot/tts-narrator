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
/// styled in `text-on-accent` through a `DefaultTextStyle` so a filled button
/// renders white text/icons without every caller specifying the color.
class PlatformButton extends StatelessWidget {
  const PlatformButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.style = PlatformButtonStyle.filled,
    this.compact = false,
  });

  /// Tap handler; null disables the button.
  final VoidCallback? onPressed;

  /// Button label.
  final Widget child;

  /// Optional leading icon (rendered inline on Cupertino, as `.icon` on
  /// Material).
  final Widget? icon;

  final PlatformButtonStyle style;

  /// Slims the button for tight toolbars: reduces Material tap-target padding
  /// ([VisualDensity.compact], zero minimum size) and Cupertino inner padding.
  /// Icons and text keep their natural size; only the padding around them
  /// shrinks.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _buildCupertino(context);
    }
    return _buildMaterial();
  }

  Widget _buildCupertino(BuildContext context) {
    final tokens = AppTokens.of(context);
    final onAccent = tokens.colors.textOnAccent;
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
    final pad = EdgeInsets.symmetric(
      horizontal: compact ? 8 : 14,
      vertical: compact ? 5 : (style == PlatformButtonStyle.outlined ? 8 : 6),
    );
    if (style == PlatformButtonStyle.outlined) {
      return CupertinoButton(
        onPressed: onPressed,
        child: Container(
          padding: pad,
          decoration: BoxDecoration(
            border: Border.all(
              color: tokens.colors.borderSubtle,
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          ),
          child: label,
        ),
      );
    }
    final accent = tokens.colors.accentPrimary;
    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      child: DefaultTextStyle(
        style: TextStyle(color: onAccent),
        // Icons resolve color from IconTheme, not DefaultTextStyle; without
        // this the root Cupertino IconTheme (accent-primary) would make icons
        // invisible on the same-colored fill.
        child: IconTheme(
          data: IconThemeData(color: onAccent),
          child: Container(
            padding: pad,
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
    final ButtonStyle? buttonStyle;
    if (compact) {
      buttonStyle = (style == PlatformButtonStyle.outlined
              ? OutlinedButton.styleFrom
              : FilledButton.styleFrom)(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );
    } else {
      buttonStyle = null;
    }
    if (style == PlatformButtonStyle.outlined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        style: buttonStyle,
        icon: icon ?? const SizedBox.shrink(),
        label: child,
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: buttonStyle,
      icon: icon ?? const SizedBox.shrink(),
      label: child,
    );
  }
}