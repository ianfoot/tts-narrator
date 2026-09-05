import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-aware icon-only button: [CupertinoButton] (transparent) on macOS,
/// [IconButton] elsewhere.
///
/// [tooltip] renders on every platform: the macOS build wraps the button in a
/// [Localizations.override] for Material's localizations so the Material
/// [Tooltip] works even though the app shell is a [CupertinoApp] (which
/// provides no Material localizations of its own).
class PlatformIconButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final Widget button;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      button = CupertinoButton(
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        pressedOpacity: 0.6,
        borderRadius: BorderRadius.circular(6),
        child: icon,
      );
    } else {
      button = IconButton(
        icon: icon,
        onPressed: onPressed,
      );
    }
    if (tooltip == null) return button;
    return Localizations.override(
      context: context,
      delegates: const [DefaultMaterialLocalizations.delegate],
      child: Tooltip(message: tooltip!, child: button),
    );
  }
}
