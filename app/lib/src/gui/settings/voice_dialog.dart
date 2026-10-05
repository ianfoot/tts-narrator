import 'package:flutter/cupertino.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart' show VoiceGender;

import '../../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/app_text_field.dart';
import 'settings_labels.dart';

/// The values collected by the add/edit voice dialog.
typedef VoiceDraft = ({String label, String id, VoiceGender? gender});

/// Add/edit voice form: a label, the provider voice id, and a gender tag.
///
/// The label and the id are separate fields on purpose. The id is what gets sent
/// to the provider and is what the picker matches on, so it is the field a user
/// is most likely to paste in; the label is cosmetic and is what a reader
/// recognises. A blank label falls back to the id, which is what a model keyed
/// by id (Kokoro) wants anyway.
///
/// Returns null when cancelled. The caller applies the draft to the store, so
/// this widget stays free of config-directory knowledge and of the rejection
/// rules (duplicate ids, blank fields) that live with the data.
Future<VoiceDraft?> showVoiceDialog(
  BuildContext context, {
  required String title,
  String initialLabel = '',
  String initialId = '',
  VoiceGender? initialGender,
}) => showCupertinoDialog<VoiceDraft>(
  context: context,
  builder: (context) => _VoiceDialog(
    title: title,
    initialLabel: initialLabel,
    initialId: initialId,
    initialGender: initialGender,
  ),
);

class _VoiceDialog extends StatefulWidget {
  const _VoiceDialog({
    required this.title,
    required this.initialLabel,
    required this.initialId,
    required this.initialGender,
  });

  final String title;
  final String initialLabel;
  final String initialId;
  final VoiceGender? initialGender;

  @override
  State<_VoiceDialog> createState() => _VoiceDialogState();
}

class _VoiceDialogState extends State<_VoiceDialog> {
  late final TextEditingController _label = TextEditingController(
    text: widget.initialLabel,
  );
  late final TextEditingController _id = TextEditingController(
    text: widget.initialId,
  );
  late VoiceGender? _gender = widget.initialGender;

  @override
  void dispose() {
    _label.dispose();
    _id.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _label.text.trim();
    final id = _id.text.trim();
    final resolvedLabel = label.isEmpty ? id : label;
    // A fully blank form is a no-op rather than an error: the store rejects it
    // with a message naming the problem, and there is nothing to report yet.
    if (resolvedLabel.isEmpty) return;
    Navigator.of(context).pop(
      (label: resolvedLabel, id: id, gender: _gender),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            _FieldLabel(l10n.gui_settings_voiceDialogLabel),
            AppTextField(
              key: const Key('voiceDialogLabelField'),
              controller: _label,
              hintText: l10n.gui_settings_voiceDialogLabelHint,
            ),
            const SizedBox(height: 12),
            _FieldLabel(l10n.gui_settings_voiceDialogId),
            AppTextField(
              key: const Key('voiceDialogIdField'),
              controller: _id,
              hintText: l10n.gui_settings_voiceDialogIdHint,
            ),
            const SizedBox(height: 12),
            _FieldLabel(l10n.gui_settings_columnGender),
            Align(
              alignment: Alignment.centerLeft,
              child: AppDropdown<VoiceGender?>(
                key: const Key('voiceDialogGenderDropdown'),
                value: _gender,
                hint: l10n.gui_settings_genderAny,
                items: settingsGenderItems(l10n),
                onChanged: (value) => setState(() => _gender = value),
              ),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          key: const Key('voiceDialogCancelButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.gui_settings_voiceDialogCancel),
        ),
        CupertinoDialogAction(
          key: const Key('voiceDialogSaveButton'),
          isDefaultAction: true,
          onPressed: _submit,
          child: Text(l10n.gui_settings_voiceDialogSave),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: tokens.typography.body),
      ),
    );
  }
}
