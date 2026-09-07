import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-aware indeterminate/spinner activity indicator:
/// [CupertinoActivityIndicator] on macOS, [CircularProgressIndicator]
/// elsewhere.
class PlatformActivityIndicator extends StatelessWidget {
  const PlatformActivityIndicator({super.key, this.size = 16.0});

  final double size;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return CupertinoActivityIndicator(radius: size / 2);
    }
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
