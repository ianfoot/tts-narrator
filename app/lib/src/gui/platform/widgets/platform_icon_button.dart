import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-aware icon-only button: [CupertinoButton] (transparent) on macOS,
/// [IconButton] elsewhere.
class PlatformIconButton extends StatelessWidget {
  const PlatformIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
  });

  final Widget icon;

  /// Only rendered on non-macOS (Material) platforms — Cupertino has no native
  /// tooltip and `Tooltip` requires MaterialLocalizations, which a CupertinoApp
  /// does not provide.
  final String? tooltip;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return CupertinoButton(
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        pressedOpacity: 0.6,
        borderRadius: BorderRadius.circular(6),
        child: icon,
      );
    }
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}