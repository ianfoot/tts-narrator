import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../platform/widgets/platform_dropdown.dart';
import '../platform/widgets/platform_segmented.dart';
import '../theme/app_text_tokens.dart' show TextTokens;
import '../theme/app_tokens.dart';
import 'settings_labels.dart';

/// The voice half of the settings rail: an optional narrator-gender filter
/// (only when the active model's voice list is gender-tagged) above the voice
/// alias picker. Extracted from the model section so per-model panels can
/// compose it independently of the model picker.
///
/// Every control writes straight to [AppController], which notifies the editor
/// so the status-bar estimate stays live. Values are re-read from the
/// controller on every build, so a model switch landing in the parent section
/// re-renders this picker with the new voice list.
class VoicePickerWidget extends StatelessWidget {
  const VoicePickerWidget({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsFieldLabel(tokens, TextTokens.gui_settings_voiceAliasLabel),
        if (controller.hasGenderTags) ...[
          const SizedBox(height: 12),
          PlatformSegmentedControl<VoiceGender>(
            key: const Key('genderControl'),
            tooltip: TextTokens.gui_settings_genderControlTooltip,
            value: controller.voiceGenderFilter,
            items: const [
              (VoiceGender.neutral, TextTokens.gui_settings_genderAny),
              (VoiceGender.female, TextTokens.gui_settings_genderFemale),
              (VoiceGender.male, TextTokens.gui_settings_genderMale),
            ],
            onChanged: (g) => controller.voiceGenderFilter = g,
          ),
          const SizedBox(height: 12),
        ],
        PlatformDropdown<String>(
          key: const Key('voiceDropdown'),
          tooltip: TextTokens.gui_settings_voiceDropdownTooltip,
          value: _selectedVoiceLabel,
          items: controller.voiceItems,
          hint: TextTokens.gui_settings_selectVoiceHint,
          onChanged: (label) => controller.applyVoiceLabel(label),
        ),
      ],
    );
  }

  /// The voice entry currently selected in the picker. Matches the controller's
  /// friendly label first (an alias pick or a config default), then falls back
  /// to a label equal to the raw voice id so free-form passthrough entries
  /// (e.g. the default voice without an alias) still highlight.
  String? get _selectedVoiceLabel {
    final label = controller.voiceLabel;
    for (final entry in controller.voiceItems) {
      if (entry.$1 == label) return entry.$1;
    }
    final voice = controller.voice;
    for (final entry in controller.voiceItems) {
      if (entry.$1 == voice) return entry.$1;
    }
    return null;
  }
}
