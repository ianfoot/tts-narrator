import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-aware settings group: a muted title above its [child], bordered
/// group styling on macOS (Cupertino-like section) and a plain labeled column
/// elsewhere.
class PlatformSection extends StatelessWidget {
  const PlatformSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _buildCupertino(context);
    }
    return _buildMaterial(context);
  }

  Widget _buildCupertino(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                  ? CupertinoColors.systemGrey
                  : CupertinoColors.systemGrey,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                ? CupertinoColors.darkBackgroundGray
                : CupertinoColors.white,
            border: Border(
              bottom: BorderSide(
                color: CupertinoColors.separator,
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ],
    );
  }

  Widget _buildMaterial(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ],
    );
  }
}