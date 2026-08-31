import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-aware full-screen page: Cupertino on macOS, Material elsewhere.
/// Replaces the Scaffold/CupertinoPageScaffold pair so the editor reuses one
/// widget tree on every platform.
class PlatformPage extends StatelessWidget {
  const PlatformPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return CupertinoPageScaffold(child: SafeArea(child: child));
    }
    return Scaffold(body: SafeArea(child: child));
  }
}