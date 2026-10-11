import 'package:flutter/cupertino.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_text_field.dart';

/// Asks for the name to file a designed voice under, or to rename one with.
///
/// A single-field dialog because there is only ever one thing to decide: the
/// clip, the transcript and the prose it came from are already settled. Returns
/// null when cancelled, and the caller applies it — so the rejection rules
/// (blank names, ids already taken) stay with the store rather than being
/// restated here.
///
/// The [key] parameter exists so a test can tell the save and rename dialogs
/// apart; both would otherwise open a field with the same key.
Future<String?> showVoiceNameDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String saveLabel,
  required Key fieldKey,
  required Key saveKey,
  String initialName = '',
}) => showCupertinoDialog<String>(
  context: context,
  builder: (context) => _VoiceNameDialog(
    title: title,
    label: label,
    saveLabel: saveLabel,
    fieldKey: fieldKey,
    saveKey: saveKey,
    initialName: initialName,
  ),
);

class _VoiceNameDialog extends StatefulWidget {
  const _VoiceNameDialog({
    required this.title,
    required this.label,
    required this.saveLabel,
    required this.fieldKey,
    required this.saveKey,
    required this.initialName,
  });

  final String title;
  final String label;
  final String saveLabel;
  final Key fieldKey;
  final Key saveKey;
  final String initialName;

  @override
  State<_VoiceNameDialog> createState() => _VoiceNameDialogState();
}

class _VoiceNameDialogState extends State<_VoiceNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    // A blank form is a no-op rather than an error: there is nothing to name yet,
    // and a store rejection would only report the same thing.
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(widget.label, style: tokens.typography.body),
              ),
              AppTextField(
                key: widget.fieldKey,
                controller: _name,
                autofocus: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          key: const Key('voiceNameDialogCancelButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.gui_voiceLibrary_cancel),
        ),
        CupertinoDialogAction(
          key: widget.saveKey,
          isDefaultAction: true,
          onPressed: _submit,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}