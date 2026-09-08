import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Platform-aware single-select dropdown: a [CupertinoMenuAnchor] popup button
/// on macOS (no Material dependency), a [DropdownButton] inside an
/// [InputDecorator] elsewhere.
///
/// [value] is the currently selected item value, or null when nothing is
/// selected (renders [hint]). Selecting calls [onChanged] with the new value.
class PlatformDropdown<T> extends StatelessWidget {
  const PlatformDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
    this.tooltip,
  });

  /// Selected item value (from [items]); null shows [hint].
  final T? value;

  /// Selectable entries: the value and its display label.
  final List<(T value, String label)> items;

  /// Called when the user picks an entry.
  final ValueChanged<T>? onChanged;

  /// Optional floating/group label (rendered on Material; ignored on Cupertino).
  final String? label;

  /// Hover text shown when the mouse sits on the dropdown.
  final String? tooltip;

  /// Placeholder shown when [value] is null.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    Widget dropdown;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      dropdown = _buildCupertino();
    } else {
      dropdown = _buildMaterial(context);
    }
    return tooltip == null ? dropdown : Localizations.override(
      context: context,
      delegates: const [DefaultMaterialLocalizations.delegate],
      child: Tooltip(message: tooltip!, child: dropdown),
    );
  }

  Widget _buildCupertino() {
    final selectedIndex = items.indexWhere((it) => it.$1 == value);
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

  Widget _buildMaterial(BuildContext context) {
    final colors = AppTokens.of(context).colors;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          iconEnabledColor: colors.textPrimary.withValues(alpha: 0.85),
          hint: hint == null
              ? null
              : Text(hint!, overflow: TextOverflow.ellipsis),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item.$1,
                child: Text(item.$2, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged?.call(next);
          },
        ),
      ),
    );
  }
}
