import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Visual weighting for [AppButton].
enum AppButtonStyle { filled, outlined }

/// Accent-primary button: filled or outlined, single Cupertino dialect.
///
/// The filled style is a custom accent-primary container rather than
/// `CupertinoButton.filled`, whose SDK-default geometry is taller than the
/// app's 44px toolbar and clipped the toolbar Narrate button. The child is
/// styled in `text-on-accent` through a `DefaultTextStyle` so a filled button
/// renders white text/icons without every caller specifying the color.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.style = AppButtonStyle.filled,
    this.compact = false,
    this.tooltip,
  });

  /// Tap handler; null disables the button.
  final VoidCallback? onPressed;

  /// Button label.
  final Widget child;

  /// Optional leading icon (rendered inline).
  final Widget? icon;

  final AppButtonStyle style;

  /// Slims the button for tight toolbars: reduces inner padding. Icons and
  /// text keep their natural size; only the padding around them shrinks.
  final bool compact;

  /// Hover text shown when the mouse sits on the button.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final onAccent = tokens.colors.textOnAccent;
    final label = icon == null
        ? child
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [icon!, const SizedBox(width: 6), child],
          );
    final pad = EdgeInsets.symmetric(
      horizontal: compact ? 8 : 14,
      vertical: compact ? 5 : (style == AppButtonStyle.outlined ? 8 : 6),
    );
    final Widget button;
    if (style == AppButtonStyle.outlined) {
      button = CupertinoButton(
        onPressed: onPressed,
        // Zero out the SDK padding (the filled branch does the same) so the
        // container's own `pad` decides the height. CupertinoButton's default
        // 16px all-round padding consumed the toolbar's tight 44px and
        // collapsed the label paragraph to zero height, hiding the text.
        padding: EdgeInsets.zero,
        child: DefaultTextStyle(
          style: TextStyle(color: tokens.colors.textPrimary),
          child: Container(
            padding: pad,
            decoration: BoxDecoration(
              border: Border.all(color: tokens.colors.borderSubtle, width: 0.8),
              borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
            ),
            child: label,
          ),
        ),
      );
    } else {
      final accent = tokens.colors.accentPrimary;
      button = CupertinoButton(
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
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
