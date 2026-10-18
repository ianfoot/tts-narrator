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
/// that sends no voice id and writes its narrator from prose instead, unless it
/// can clone from a clip — such a model has no rows to pick between otherwise,
/// and an empty dropdown under a "Voice" label would be a lie. The language
/// dropdown stays either way: it narrows the voice list, but it is also the
/// `lang_code` a model synthesises in.
class VoicePickerWidget extends StatelessWidget {
  const VoicePickerWidget({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    // A reference clip takes the voice field's place on the wire, so the two
    // are one choice rather than two: the dropdown lists the model's voices and,
    // when it can take a clip, the saved voices, and picking either clears the
    // other. The gender control narrows only the model's own voices.
    final takesVoice = controller.takesVoice;
    final showPicker = controller.showVoicePicker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPicker)
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
        if (showPicker) ...[
          const SizedBox(height: 12),
          if (takesVoice && controller.hasGenderTags) ...[
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
            onChanged: (id) => controller.selectVoice(id),
          ),
        ],
      ],
    );
  }

  /// The dropdown row currently selected, or null when the run is speaking with
  /// a clip the picker does not know.
  ///
  /// Matched on the id alone, because a label cannot: a model may carry two voices
  /// of one name (Kokoro has three Santas), and a label match would select the
  /// first however the reader clicked. It also leaves the picker able to show a
  /// selection when a voice id was typed in directly.
  String? get _selectedVoiceId {
    final saved = controller.selectedCustomVoiceId;
    if (saved != null) return saved;
    final voice = controller.voice;
    if (voice.isEmpty) return null;
    for (final entry in controller.voiceItems) {
      if (entry.$1 == voice) return voice;
    }
    return null;
  }
}
