import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;

/// Full-height multiline editor via [expands].
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText,
    this.maxLines = 1,
    this.expands = false,
    this.keyboardType,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.style,
    this.hintStyle,
    this.tooltip,
  });

  final TextEditingController controller;

  /// Called whenever the user edits the text.
  final ValueChanged<String>? onChanged;

  /// Placeholder shown while empty.
  final String? hintText;

  /// Number of lines (null unbounded). Must be null when [expands] is true.
  final int? maxLines;

  /// Fill the vertical space of the parent.
  final bool expands;

  /// Restricts the input to a specific type (e.g. numbers).
  final TextInputType? keyboardType;

  final bool enabled;

  final bool autofocus;

  /// Masks the input (password-style) for secrets such as the API key.
  final bool obscureText;

  final TextStyle? style;

  /// Style for the placeholder/hint text (e.g. a dimmed placeholder).
  final TextStyle? hintStyle;

  /// Hover text shown when the mouse interacts with the text field.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final textField = CupertinoTextField(
      controller: controller,
      onChanged: onChanged,
      placeholder: hintText,
      maxLines: maxLines,
      expands: expands,
      keyboardType: keyboardType,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
      style: style,
      placeholderStyle: hintStyle,
      textAlignVertical: TextAlignVertical.top,
      padding: expands ? const EdgeInsets.all(4) : const EdgeInsets.all(12),
      decoration: expands ? const BoxDecoration() : null,
    );
    if (tooltip == null) return textField;
    return Tooltip(message: tooltip!, child: textField);
  }
}
