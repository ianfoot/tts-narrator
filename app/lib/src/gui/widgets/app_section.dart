import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class AppSection extends StatelessWidget {
  const AppSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `stretch` (not `start`) so the surface container always spans the full
    // rail width. With `start` the background only widened to the section's
    // widest child, leaving a ragged edge against the neighbouring section.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _header(context, title),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTokens.of(context).colors.bgSurface,
            border: Border(
              bottom: BorderSide(
                color: AppTokens.of(context).colors.borderSubtle,
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

  static Text _header(BuildContext context, String title) {
    final tokens = AppTokens.of(context);
    return Text(
      title.toUpperCase(),
      style: tokens.typography.body.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: tokens.colors.textPrimary,
      ),
    );
  }
}
