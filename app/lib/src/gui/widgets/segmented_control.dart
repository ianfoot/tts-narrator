import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;

import '../theme/app_tokens.dart';

/// macOS-style segmented control: an elevated track with a sliding selected
/// pill, delegating to [CupertinoSlidingSegmentedControl] so the native
/// animation, thumb and separator rendering come from the framework.
class SegmentedControl<T extends Object> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.tooltip,
  });

  final T? value;
  final List<(T value, String label)> items;
  final ValueChanged<T>? onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = tokens.colors;
    final control = CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      backgroundColor: colors.bgSurfaceElevated,
      thumbColor: colors.bgSurface,
      children: {
        for (final (item, label) in items)
          item: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.control.copyWith(
              fontWeight: item == value ? FontWeight.w600 : FontWeight.w400,
              color: item == value ? colors.textPrimary : colors.textSecondary,
            ),
          ),
      },
      onValueChanged: (selected) {
        if (selected != null) onChanged?.call(selected);
      },
    );
    if (tooltip == null) return control;
    return Tooltip(message: tooltip!, child: control);
  }
}
