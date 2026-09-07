import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Platform-aware full-screen page: Cupertino on macOS, Material elsewhere.
/// Replaces the Scaffold/CupertinoPageScaffold pair so the editor reuses one
/// widget tree on every platform.
class PlatformPage extends StatelessWidget {
  const PlatformPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `bg-app` paints the whole window backdrop behind the surface columns.
    final bgApp = AppTokens.of(context).colors.bgApp;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return CupertinoPageScaffold(
        backgroundColor: bgApp,
        child: SafeArea(child: child),
      );
    }
    return Scaffold(
      backgroundColor: bgApp,
      body: SafeArea(child: child),
    );
  }
}
