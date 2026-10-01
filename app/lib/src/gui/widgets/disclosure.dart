import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Tooltip;

import '../theme/app_tokens.dart';

/// Expandable disclosure group: a tappable header (chevron + [label]) that
/// toggles [child] visibility. Collapsed by default.
class Disclosure extends StatelessWidget {
  const Disclosure({
    super.key,
    required this.label,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.caption,
    this.tooltip,
  });

  final String label;
  final bool expanded;
  final ValueChanged<bool> onToggle;
  final Widget child;

  /// Hint line shown under the header when collapsed.
  final String? caption;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final disclosure = _buildDisclosure(context);
    if (tooltip == null) return disclosure;
    return Tooltip(message: tooltip!, child: disclosure);
  }

  Widget _buildDisclosure(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = tokens.colors;
    final header = GestureDetector(
      onTap: () => onToggle(!expanded),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: colors.textPrimary.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 8),
          Text(label, style: tokens.typography.body),
        ],
      ),
    );
    if (!expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 8), child: header),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                caption!,
                style: tokens.typography.body.copyWith(color: colors.textSecondary),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 8), child: header),
        Padding(padding: const EdgeInsets.all(12), child: child),
      ],
    );
  }
}