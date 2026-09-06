import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Platform-aware single-select segmented control: a custom token-driven
/// control on macOS (modeled on System Settings' Appearance switch), a
/// Material 3 [SegmentedButton] elsewhere.
///
/// macOS renders a full-width container in `bg-surface-elevated` with an inset
/// "selected" pill in `bg-surface` that slides between segments via
/// [AnimatedAlign] — the compact capsule macOS cues for a cheap binary/
/// ternary choice — while unselected segments stay muted in `text-secondary`.
/// All colors resolve from [AppTokens] so the control matches the rail.
///
/// [value] is the currently selected item value. Selecting calls [onChanged]
/// with the new value (like [PlatformDropdown]).
class PlatformSegmentedControl<T> extends StatelessWidget {
  const PlatformSegmentedControl({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  /// Selected item value (from [items]).
  final T? value;

  /// Selectable entries: the value and its display label.
  final List<(T value, String label)> items;

  /// Called when the user picks an entry.
  final ValueChanged<T>? onChanged;

  /// macOS: the sliding selection glides between segments over 130ms on an
  /// ease-in-out curve, mirroring the system control's motion.
  static const _slideDuration = Duration(milliseconds: 130);

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _buildCupertino(context);
    }
    return _buildMaterial();
  }

  Widget _buildCupertino(BuildContext context) {
    final colors = AppTokens.of(context).colors;
    final selectedIndex = items.indexWhere((it) => it.$1 == value);
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

  Widget _buildMaterial() {
    // A null [value] selects whichever item carries a null value (e.g. an
    // "Any" segment); keep the set non-empty so [SegmentedButton] renders.
    final selected = <T>{
      if (value != null) value!,
      if (value == null)
        for (final it in items)
          if (it.$1 == null) it.$1,
    };
    return SegmentedButton<T>(
      segments: [
        for (final item in items)
          ButtonSegment<T>(value: item.$1, label: Text(item.$2)),
      ],
      selected: selected,
      onSelectionChanged: (selection) {
        if (onChanged == null) return;
        // [emptySelectionAllowed] is false, so [selection] is never empty;
        // a null value selects the null-valued segment (e.g. "Any").
        onChanged!(selection.first);
      },
      showSelectedIcon: false,
    );
  }
}

/// One tappable segment label inside the macOS control.
class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = tokens.colors;
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
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}