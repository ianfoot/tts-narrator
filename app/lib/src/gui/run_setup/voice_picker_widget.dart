import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../../../l10n/app_localizations.dart';
import '../controller/app_controller.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/segmented_control.dart';
import 'run_setup_labels.dart';

/// The voice picker of the run-setup panel: an optional language dropdown and
/// narrator-gender filter (only when the active model declares them) above the
/// voice alias picker. Extracted from the model section so per-model panels can
/// compose it independently of the model picker.
///
/// Values are re-read from the controller on every build, so a model switch
/// landing in the parent section re-renders this picker with the new list.
///
/// The label, gender filter and voice dropdown disappear together for a model
/// that sends no voice id and writes its narrator from prose instead — such a
/// model has no rows to pick between, and an empty dropdown under a "Voice" label
/// would be a lie. The language dropdown stays: it narrows the voice list, but it
/// is also the `lang_code` a model synthesises in.
class VoicePickerWidget extends StatelessWidget {
  const VoicePickerWidget({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final takesVoice = controller.takesVoice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (takesVoice)
          runSetupFieldLabel(tokens, l10n.gui_run_setup_voiceAliasLabel),
        if (controller.hasLanguages) ...[
          const SizedBox(height: 12),
          AppDropdown<String>(
            key: const Key('languageDropdown'),
            tooltip: l10n.gui_run_setup_languageDropdownTooltip,
            value: controller.voiceLanguage,
            items: controller.languageItems,
            hint: l10n.gui_run_setup_selectLanguageHint,
            onChanged: (code) => controller.applyVoiceLanguage(code),
          ),
        ],
        if (takesVoice) ...[
          const SizedBox(height: 12),
          if (controller.hasGenderTags) ...[
            SegmentedControl<VoiceGender>(
              key: const Key('genderControl'),
              tooltip: l10n.gui_run_setup_genderControlTooltip,
              value: controller.voiceGenderFilter,
              items: [
                (VoiceGender.neutral, l10n.gui_run_setup_genderAny),
                (VoiceGender.female, l10n.gui_run_setup_genderFemale),
                (VoiceGender.male, l10n.gui_run_setup_genderMale),
              ],
              onChanged: (g) => controller.voiceGenderFilter = g,
            ),
            const SizedBox(height: 12),
          ],
          AppDropdown<String>(
            key: const Key('voiceDropdown'),
            tooltip: l10n.gui_run_setup_voiceDropdownTooltip,
            value: _selectedVoiceId,
            items: controller.voiceItems,
            hint: l10n.gui_run_setup_selectVoiceHint,
            onChanged: (id) => controller.applyVoiceId(id),
          ),
        ],
      ],
    );
  }

  /// The voice entry currently selected in the picker, as the id the dropdown
  /// carries it under.
  ///
  /// Matched on the id alone. The label used to be the dropdown value, which made
  /// a model with two voices of one name (Kokoro has three Santas) select the
  /// first of them however the reader clicked, and left the picker unable to
  /// show a selection when a voice id was typed in directly.
  String? get _selectedVoiceId {
    final voice = controller.voice;
    if (voice.isEmpty) return null;
    for (final entry in controller.voiceItems) {
      if (entry.$1 == voice) return voice;
    }
    return null;
  }
}
