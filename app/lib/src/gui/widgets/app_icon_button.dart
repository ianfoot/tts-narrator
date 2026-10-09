import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Enabled toolbar icons rest at ~78% opacity and step up to full
/// [AppPalette.textPrimary] only while hovered, so quiet chrome doesn't
/// compete with the labels around it.
const double kIconButtonRestOpacity = 0.78;

/// Icon-only toolbar button, single Cupertino dialect. Icons render at
/// [kIconButtonRestOpacity] when idle, full opacity on hover/press, and a
/// disabled grey (0.6 alpha) when [onPressed] is null.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
  });

  final Widget icon;

  /// Hover text shown when the mouse sits on the button.
  final String? tooltip;

  final VoidCallback? onPressed;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final enabled = widget.onPressed != null;
    final alpha = !enabled
        ? 0.6
        : _hovered
        ? 1.0
        : kIconButtonRestOpacity;
    final iconColor = tokens.colors.textPrimary.withValues(alpha: alpha);
    final themedIcon = IconTheme(
      data: IconThemeData(color: iconColor),
      child: widget.icon,
    );
    final button = CupertinoButton(
      onPressed: widget.onPressed,
      padding: const EdgeInsets.all(8),
      // Keep the icon at full brightness while pressing: the hover state
      // already telegraphs interactivity, and dimming here would dip below
      // the resting opacity (jarring against the "active = full" rule).
      pressedOpacity: 1.0,
      borderRadius: BorderRadius.circular(6),
      child: themedIcon,
    );
    final Widget hoverAware = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: button,
    );
    if (widget.tooltip == null) return hoverAware;
    return Tooltip(message: widget.tooltip!, child: hoverAware);
  }
}
