import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// macOS-style segmented control: an elevated track with a sliding selected
/// pill;
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.tooltip,
  });

  static const Duration _slideDuration = Duration(milliseconds: 130);

  final T? value;
  final List<(T value, String label)> items;
  final ValueChanged<T>? onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final control = _buildControl(context);
    if (tooltip == null) return control;
    return Tooltip(message: tooltip!, child: control);
  }

  Widget _buildControl(BuildContext context) {
    final colors = AppTokens.of(context).colors;
    final selectedIndex = items.indexWhere((item) => item.$1 == value);
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.bgSurfaceElevated,
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final n = items.length;
          final segmentWidth = constraints.maxWidth / n;
          return Stack(
            children: [
              if (selectedIndex != -1 && n > 1)
                AnimatedAlign(
                  duration: _slideDuration,
                  curve: Curves.easeInOut,
                  alignment: Alignment(-1 + 2 * selectedIndex / (n - 1), 0),
                  child: Container(
                    width: segmentWidth,
                    decoration: BoxDecoration(
                      color: colors.bgSurface,
                      border: Border.all(
                        color: colors.borderSubtle,
                        width: 0.8,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppMetrics.controlRadius - 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.overlayMuted,
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      child: _SegmentButton(
                        label: items[i].$2,
                        selected: i == selectedIndex,
                        onTap: onChanged == null
                            ? null
                            : () => onChanged!(items[i].$1),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: tokens.typography.body.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? tokens.colors.textPrimary
                  : tokens.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
