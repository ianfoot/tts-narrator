import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show TextOverflow, Tooltip;

import '../theme/app_tokens.dart';

/// Single-select dropdown: a [CupertinoMenuAnchor] popup button.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.tooltip,
  });

  final T? value;
  final List<(T value, String label)> items;
  final ValueChanged<T>? onChanged;

  /// Placeholder shown when no item is selected.
  final String? hint;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dropdown = _buildDropdown(context);
    if (tooltip == null) return dropdown;
    return Tooltip(message: tooltip!, child: dropdown);
  }

  Widget _buildDropdown(BuildContext context) {
    final selectedIndex = items.indexWhere((item) => item.$1 == value);
    final selectedLabel = selectedIndex == -1
        ? (hint ?? '')
        : items[selectedIndex].$2;
    return CupertinoMenuAnchor(
      enableLongPressToOpen: false,
      menuChildren: [
        for (final item in items)
          CupertinoMenuItem(
            child: Text(item.$2),
            onPressed: () {
              if (onChanged != null) onChanged!(item.$1);
            },
          ),
      ],
      builder: (context, controller, child) {
        final tokens = AppTokens.of(context);
        final colors = tokens.colors;
        return CupertinoButton(
          onPressed: controller.open,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
          pressedOpacity: 0.6,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  selectedLabel,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.control.copyWith(
                    color: selectedIndex == -1
                        ? colors.textSecondary
                        : colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_down,
                size: 14,
                color: colors.textPrimary.withValues(alpha: 0.85),
              ),
            ],
          ),
        );
      },
    );
  }
}
