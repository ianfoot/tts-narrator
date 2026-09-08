import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-aware text field: [CupertinoTextField] on macOS, [TextField]
/// elsewhere. Supports a full-height multiline editor via [expands].
class PlatformTextField extends StatelessWidget {
  const PlatformTextField({
    super.key,
    this.controller,
    this.onChanged,
    this.hintText,
    this.maxLines = 1,
    this.expands = false,
    this.keyboardType,
    this.enabled = true,
    this.autofocus = false,
    this.style,
    this.hintStyle,
    this.tooltip,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? hintText;

  /// Number of lines (null unbounded). Must be null when [expands] is true.
  final int? maxLines;

  /// Fill the vertical space of the parent.
  final bool expands;

  final TextInputType? keyboardType;
  final bool enabled;
  final bool autofocus;
  final TextStyle? style;

  /// Style for the placeholder/hint text (e.g. a dimmed placeholder).
  final TextStyle? hintStyle;

  /// Hover text shown when the mouse interacts with the text field.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget textField;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      textField = CupertinoTextField(
        controller: controller,
        onChanged: onChanged,
        placeholder: hintText,
        maxLines: maxLines,
        expands: expands,
        keyboardType: keyboardType,
        enabled: enabled,
        autofocus: autofocus,
        style: style,
        placeholderStyle: hintStyle,
        textAlignVertical: TextAlignVertical.top,
        padding: expands ? const EdgeInsets.all(4) : const EdgeInsets.all(12),
        decoration: expands ? const BoxDecoration() : null,
      );
    } else {
      textField = TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: maxLines,
      expands: expands,
      keyboardType: keyboardType,
      enabled: enabled,
      autofocus: autofocus,
      style: style,
      textAlignVertical: TextAlignVertical.top,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: hintStyle,
        border: InputBorder.none,
        isDense: true,
      ),
    );
    }
    return tooltip == null ? textField : Localizations.override(
      context: context,
      delegates: const [DefaultMaterialLocalizations.delegate],
      child: Tooltip(message: tooltip!, child: textField),
    );
  }
}
