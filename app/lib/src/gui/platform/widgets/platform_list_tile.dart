import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-aware list tile: [CupertinoListTile] on macOS, [ListTile]
/// elsewhere. Both render a leading/title/subtitle/trailing row without
/// requiring a Material ancestor on the macOS path.
class PlatformListTile extends StatelessWidget {
  const PlatformListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return CupertinoListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
      );
    }
    return ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
    );
  }
}
