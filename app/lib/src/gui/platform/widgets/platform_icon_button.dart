import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Enabled toolbar icons rest at ~78% opacity and step up to full
/// [AppPalette.textPrimary] only while hovered (or pressed), so quiet chrome
/// like the top-left header cluster doesn't compete with the text labels
/// around it.
const double kIconButtonRestOpacity = 0.78;

/// Platform-aware icon-only button: [CupertinoButton] (transparent) on macOS,
/// [IconButton] elsewhere.
///
/// Icons render at [kIconButtonRestOpacity] when enabled and idle, brighten to
/// full opacity on hover/press (the "active" state), and drop to a disabled
/// grey (0.6 alpha) when [onPressed] is null.
///
/// [tooltip] renders on every platform: the macOS build wraps the button in a
/// [Localizations.override] for Material's localizations so the Material
/// [Tooltip] works even though the app shell is a [CupertinoApp] (which
/// provides no Material localizations of its own).
class PlatformIconButton extends StatefulWidget {
  const PlatformIconButton({
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
  State<PlatformIconButton> createState() => _PlatformIconButtonState();
}

class _PlatformIconButtonState extends State<PlatformIconButton> {
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
    final Widget button;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      button = CupertinoButton(
        onPressed: widget.onPressed,
        padding: const EdgeInsets.all(8),
        // Keep the icon at full brightness while pressing: the hover state
        // already telegraphs interactivity, and dimming here would dip below
        // the resting opacity (jarring against the "active = full" rule).
        pressedOpacity: 1.0,
        borderRadius: BorderRadius.circular(6),
        child: themedIcon,
      );
    } else {
      button = IconButton(icon: themedIcon, onPressed: widget.onPressed);
    }
    final Widget hoverAware = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: button,
    );
    if (widget.tooltip == null) return hoverAware;
    return Localizations.override(
      context: context,
      delegates: const [DefaultMaterialLocalizations.delegate],
      child: Tooltip(message: widget.tooltip!, child: hoverAware),
    );
  }
}
