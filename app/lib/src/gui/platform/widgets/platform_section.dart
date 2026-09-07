import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Platform-aware settings group: a muted title above its [child], bordered
/// group styling on macOS (Cupertino-like section) and a plain labeled column
/// elsewhere.
class PlatformSection extends StatelessWidget {
  const PlatformSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _buildCupertino(context);
    }
    return _buildMaterial(context);
  }

  /// Tier 1 category header (e.g. "MODEL & VOICE", "RUN"): 11pt semibold,
  /// uppercase, secondary, with tracking. Uniform 16px top / 8px bottom.
  static Text _header(BuildContext context, String title) {
    final tokens = AppTokens.of(context);
    return Text(
      title.toUpperCase(),
      style: tokens.typography.caption.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: tokens.colors.textSecondary,
      ),
    );
  }

  Widget _buildCupertino(BuildContext context) {
    final colors = AppTokens.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _header(context, title),
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.bgSurface,
            border: Border(
              bottom: BorderSide(color: colors.borderSubtle, width: 0.5),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _header(context, title),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ],
    );
  }
}
