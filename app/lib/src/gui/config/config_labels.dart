import 'package:tts_narrator_core/tts_narrator_core.dart' show TtsModelProfile,
    VoiceGender;

import '../../../l10n/app_localizations.dart';

/// Row label for [model] in the config screen's model list: the alias, with the
/// model id behind it when the profile carries a display name, so two profiles
/// that share a display name stay tellable apart. The alias alone is not enough
/// — it is the file stem, which is an implementation detail of the config
/// layout rather than something a reader recognises.
String configModelLabel(TtsModelProfile model, AppLocalizations l10n) {
  final display = model.displayName;
  if (display == null || display.isEmpty || display == model.alias) {
    return model.alias;
  }
  return '$display · ${model.alias}';
}

/// Display strings for the providers & voices screen.
///
/// Kept beside the screen rather than in `controller/l10n_labels.dart` because
/// they are pure widget-side presentation for one view: the controllers that own
/// the underlying data return ids, genders and aliases, never strings.
extension ConfigVoiceGenderX on VoiceGender? {
  /// Localized label for the gender column. Named `configLabel` rather than
  /// `label` because [VoiceGender.label] already exists in core as the raw
  /// English enum name, and an instance member would win over the extension.
  String configLabel(AppLocalizations l10n) => switch (this) {
    VoiceGender.male => l10n.gui_config_genderMale,
    VoiceGender.female => l10n.gui_config_genderFemale,
    VoiceGender.neutral => l10n.gui_config_genderNeutral,
    null => l10n.gui_config_genderAny,
  };
}

/// Dropdown items for the gender field, "not set" first so clearing a tag is
/// one click rather than a scroll away.
List<(VoiceGender?, String)> configGenderItems(AppLocalizations l10n) => [
  (null, l10n.gui_config_genderAny),
  for (final gender in VoiceGender.values) (
    gender,
    gender.configLabel(l10n),
  ),
];
