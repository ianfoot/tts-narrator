import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Platform-aware expandable disclosure group: a tappable header (chevron +
/// [label]) that toggles [child] visibility. Collapsed by default.
class PlatformDisclosure extends StatelessWidget {
  const PlatformDisclosure({
    super.key,
    required this.label,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.caption,
    this.tooltip,
  });

  /// The header label (e.g. "Advanced Voice ID").
  final String label;

  /// Whether the child is currently revealed.
  final bool expanded;

  /// Called with the next expanded state when the header is tapped.
  final ValueChanged<bool> onToggle;

  /// The content revealed when [expanded].
  final Widget child;

  /// Optional caption below the header while collapsed.
  final String? caption;

  /// Hover text shown when the mouse interacts with the disclosure header.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = AppTokens.of(context).colors;
    final textStyle = AppTokens.of(context).typography.caption
        .copyWith(color: colors.textSecondary);
    final header = GestureDetector(
      onTap: () => onToggle(!expanded),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _chevron(context),
            size: 16,
            color: colors.textPrimary.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 8),
          Text(label, style: textStyle),
        ],
      ),
    );
    Widget result;
    if (!expanded) {
      result = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 8), child: header),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(caption!, style: textStyle),
            ),
        ],
      );
    } else {
      result = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 8), child: header),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      );
    }
    return tooltip == null ? result : Localizations.override(
      context: context,
      delegates: const [DefaultMaterialLocalizations.delegate],
      child: Tooltip(message: tooltip!, child: result),
    );
  }

  /// Platform-native chevron: CupertinoIcons on macOS, Material expand icon
  /// elsewhere.
  static IconData _chevron(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return CupertinoIcons.chevron_right;
    }
    return Icons.expand_more;
  }
}
