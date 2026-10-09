import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;

import '../theme/app_tokens.dart';

/// Expandable disclosure group: a tappable header (chevron + [label]) that
/// toggles [child] visibility, driven entirely by the caller's [expanded].
/// Callers own that state and start it collapsed; while collapsed the optional
/// [caption] stands in as a hint for the hidden [child].
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

  /// The header glyph: a right-pointing chevron when collapsed, flipping to
  /// down-pointing when expanded so the header carries the open/closed state
  /// visually. Cupertino glyphs on every platform, as in `AppDropdown`.
  static IconData _chevron(bool expanded) =>
      expanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right;

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
            _chevron(expanded),
            size: 16,
            color: colors.textPrimary.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 8),
          Text(label, style: tokens.typography.body),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 8), child: header),
        if (!expanded && caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              caption!,
              style: tokens.typography.body.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        if (expanded) Padding(padding: const EdgeInsets.all(12), child: child),
      ],
    );
  }
}
