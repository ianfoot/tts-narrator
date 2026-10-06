// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get app_title => 'TTS Narrator';

  @override
  String get app_untitledDocument => 'untitled.txt';

  @override
  String get app_fileTypeGroup => 'Text';

  @override
  String core_plurals_segment(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'segments',
      one: 'segment',
    );
    return '$_temp0';
  }

  @override
  String core_plurals_word(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'words',
      one: 'word',
    );
    return '$_temp0';
  }

  @override
  String core_plurals_minute(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mins',
      one: 'min',
    );
    return '$_temp0';
  }

  @override
  String core_plurals_character(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'characters',
      one: 'character',
    );
    return '$_temp0';
  }

  @override
  String core_plurals_file(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'files',
      one: 'file',
    );
    return '$_temp0';
  }

  @override
  String get gui_controller_errors_noModelConfigured =>
      'No voice model is configured. Download the starter configs, or add model files to the voice config directory.';

  @override
  String gui_controller_errors_noVoiceSelected(String modelAlias) {
    return 'No voice selected for \"$modelAlias\" — pick an alias or set a default in the voice config.';
  }

  @override
  String get gui_controller_errors_cannotOpenTextFile =>
      'Cannot open text file';

  @override
  String get gui_controller_blockReasons_emptyText => 'Editor text is empty';

  @override
  String get gui_controller_blockReasons_emptyVoiceDesign =>
      'Describe the voice in the Voice design box before narrating';

  @override
  String get gui_controller_blockReasons_alreadyRunning =>
      'Narration is already running.';

  @override
  String get gui_editor_toolbar_narrate => 'Narrate';

  @override
  String get gui_editor_toolbar_playFull => 'Play Full';

  @override
  String get gui_editor_toolbar_stop => 'Stop';

  @override
  String gui_editor_toolbar_appearanceTooltip(String mode) {
    return 'Appearance: $mode';
  }

  @override
  String get gui_editor_toolbar_showHideRunSetup => 'Show / hide run setup';

  @override
  String get gui_editor_toolbar_settings => 'Settings';

  @override
  String get gui_editor_toolbar_setOutputFolder => 'Set output folder';

  @override
  String get gui_editor_toolbar_openTextFile => 'Open text file';

  @override
  String get gui_editor_toolbar_save => 'Save';

  @override
  String get gui_editor_toolbar_cleanupSegments => 'Clean up segments';

  @override
  String get gui_editor_toolbar_themeModeAuto => 'Auto';

  @override
  String get gui_editor_toolbar_themeModeLight => 'Light';

  @override
  String get gui_editor_toolbar_themeModeDark => 'Dark';

  @override
  String get gui_editor_hintText => 'Type, paste text, or open a .txt file...';

  @override
  String gui_editor_cannotNarratePrefix(String message) {
    return 'Cannot narrate: $message';
  }

  @override
  String gui_editor_statusBar_wordCharCount(
    String words,
    String wordLabel,
    String chars,
    String charLabel,
  ) {
    return '$words $wordLabel · $chars $charLabel';
  }

  @override
  String gui_editor_statusBar_estimate(
    int segments,
    String segmentLabel,
    String minutes,
    String minuteLabel,
    String cost,
  ) {
    return '$segments $segmentLabel · ~$minutes $minuteLabel · ~$cost est.';
  }

  @override
  String get gui_run_setup_header => 'Run Setup';

  @override
  String get gui_run_setup_modelVoiceSection => 'Model & voice';

  @override
  String get gui_run_setup_modelLabel => 'Model';

  @override
  String get gui_run_setup_outputFormatLabel => 'Output format';

  @override
  String get gui_format_mp3 => 'MP3';

  @override
  String get gui_format_wav => 'WAV';

  @override
  String get gui_run_setup_voiceAliasLabel => 'Voice alias';

  @override
  String get gui_run_setup_advancedVoiceId => 'Advanced Voice ID';

  @override
  String get gui_run_setup_overridesSelectedAlias => 'Overrides selected alias';

  @override
  String get gui_run_setup_freeFormVoiceHint =>
      'free-form id or provider voice';

  @override
  String get gui_run_setup_selectVoiceHint => 'Select a Voice...';

  @override
  String get gui_run_setup_languageLabel => 'Language';

  @override
  String get gui_run_setup_selectLanguageHint => 'Select a Language...';

  @override
  String get gui_run_setup_genderAny => 'Any';

  @override
  String get gui_run_setup_genderFemale => 'Female';

  @override
  String get gui_run_setup_genderMale => 'Male';

  @override
  String get gui_run_setup_modelOptionsSection => 'Model options';

  @override
  String get gui_run_setup_speedLabel => 'Speed';

  @override
  String get gui_run_setup_speedTooltip =>
      'Speech rate multiplier (1.0 = normal)';

  @override
  String get gui_run_setup_runSection => 'Run';

  @override
  String get gui_run_setup_sendWholeFile => 'Send whole file';

  @override
  String get gui_run_setup_minWordsLabel => 'Min words per segment';

  @override
  String get gui_run_setup_sampleMode => 'Sample mode';

  @override
  String get gui_run_setup_narrateFirstSegments =>
      'Narrate first segments only';

  @override
  String get gui_run_setup_skipCompletedSegments =>
      'Skip completed segments (Resume)';

  @override
  String gui_run_setup_modelDisplayFallback(String alias, String id) {
    return '$alias — $id';
  }

  @override
  String get gui_run_setup_apiKeySection => 'API key';

  @override
  String get gui_run_setup_apiKeySectionTooltip =>
      'API key for the narration provider';

  @override
  String get gui_run_setup_apiKeyStatusLabel => 'Key source';

  @override
  String get gui_run_setup_apiKeyStatusKeychain => 'Stored in keychain';

  @override
  String get gui_run_setup_apiKeyStatusConfig => 'Set in provider config';

  @override
  String get gui_run_setup_apiKeyStatusEnvironment =>
      'Set via environment variable';

  @override
  String get gui_run_setup_apiKeyStatusMissing => 'Not set';

  @override
  String get gui_run_setup_apiKeyFieldPlaceholder => 'Paste your API key here';

  @override
  String get gui_run_setup_apiKeyFieldTooltip =>
      'API key, saved to the system keychain';

  @override
  String get gui_run_setup_apiKeySave => 'Save';

  @override
  String get gui_run_setup_apiKeyRemove => 'Remove';

  @override
  String get gui_run_setup_apiKeyStoreError =>
      'Could not reach the system key store.';

  @override
  String get gui_run_setup_modelDropdownTooltip =>
      'Select the TTS model to use for narration';

  @override
  String get gui_run_setup_voiceDropdownTooltip =>
      'Choose voice for current model';

  @override
  String get gui_run_setup_sendWholeFileTooltip =>
      'Generate single audio file instead of segments';

  @override
  String get gui_run_setup_sampleModeTooltip =>
      'Generate only first N segments for testing';

  @override
  String get gui_run_setup_resumeTooltip =>
      'Skip already generated segments when resuming';

  @override
  String get gui_run_setup_minWordsSliderTooltip =>
      'Merge paragraphs shorter than this word count';

  @override
  String get gui_run_setup_voiceRawFieldTooltip =>
      'Custom voice ID or provider voice identifier';

  @override
  String get gui_run_setup_accentFieldTooltip =>
      'Voice accent description (e.g., \'southern British English\')';

  @override
  String get gui_run_setup_styleFieldTooltip =>
      'Voice style personality (e.g., \'warm, composed\')';

  @override
  String get gui_run_setup_prefixFieldTooltip =>
      'Text prepended to each paragraph';

  @override
  String get gui_run_setup_instructFieldTooltip =>
      'Describe the narrator in prose; the model designs the voice from it';

  @override
  String get gui_run_setup_sampleLenFieldTooltip =>
      'Number of paragraphs to narrate in sample mode';

  @override
  String get gui_run_setup_genderControlTooltip => 'Filter voices by gender';

  @override
  String get gui_run_setup_languageDropdownTooltip =>
      'Language sent to the model (lang_code)';

  @override
  String get gui_run_setup_advancedVoiceIdTooltip =>
      'Enter custom voice settings';

  @override
  String get gui_narration_backToEditor => 'Back to editor';

  @override
  String gui_narration_narratingTitle(String documentName) {
    return 'Narrating: $documentName';
  }

  @override
  String gui_narration_summaryPill(
    String modelName,
    String voice,
    int segments,
    String segmentLabel,
    String minutes,
    String cost,
  ) {
    return '$modelName · $voice | $segments $segmentLabel · ~$minutes min · ~$cost';
  }

  @override
  String get gui_narration_noSegmentsYet => 'No segments yet.';

  @override
  String get gui_narration_narrationComplete => 'Narration complete.';

  @override
  String get gui_narration_narrationStopped => 'Narration was stopped.';

  @override
  String gui_narration_narrationFailed(String runError) {
    return 'Narration failed: $runError';
  }

  @override
  String gui_narration_segmentLabel(int segmentNumber) {
    return 'Segment $segmentNumber';
  }

  @override
  String gui_narration_wordCountSuffix(int words, String wordLabel) {
    return ' · $words $wordLabel';
  }

  @override
  String get gui_narration_processing => 'Processing...';

  @override
  String get gui_narration_pending => 'Pending';

  @override
  String get gui_narration_play => 'Play';

  @override
  String get gui_narration_stop => 'Stop';

  @override
  String get gui_narration_resumedTooltip => 'Resumed — tap to play';

  @override
  String get gui_narration_back => 'Back';

  @override
  String get gui_narration_cancelRun => 'Cancel Run';

  @override
  String get gui_narration_confirmCancelTitle => 'Cancel active narration run?';

  @override
  String get gui_narration_confirmCancelMessage =>
      'Generation stops now; completed clips stay playable in this session.';

  @override
  String get gui_menu_appMenu => 'TTS Narrator';

  @override
  String get gui_menu_settings => 'Settings…';

  @override
  String get gui_menu_file => 'File';

  @override
  String get gui_menu_openText => 'Open Text…';

  @override
  String get gui_menu_outputFolder => 'Output Folder…';

  @override
  String get gui_menu_narrate => 'Narrate';

  @override
  String get gui_menu_clear => 'Clear';

  @override
  String get gui_menu_save => 'Save';

  @override
  String get gui_menu_saveAs => 'Save As…';

  @override
  String get gui_menu_cleanUpSegments => 'Clean Up Segments…';

  @override
  String get gui_menu_quit => 'Quit';

  @override
  String get gui_menu_edit => 'Edit';

  @override
  String get gui_menu_undo => 'Undo';

  @override
  String get gui_menu_redo => 'Redo';

  @override
  String get gui_menu_cut => 'Cut';

  @override
  String get gui_menu_copy => 'Copy';

  @override
  String get gui_menu_paste => 'Paste';

  @override
  String get gui_menu_selectAll => 'Select All';

  @override
  String get gui_menu_view => 'View';

  @override
  String get gui_menu_appearance => 'Appearance';

  @override
  String get gui_menu_themeModeAuto => 'Auto';

  @override
  String get gui_menu_themeModeLight => 'Light';

  @override
  String get gui_menu_themeModeDark => 'Dark';

  @override
  String get gui_menu_toggleRunSetupPanel => 'Toggle Run Setup Panel';

  @override
  String get gui_menu_window => 'Window';

  @override
  String get gui_menu_checkmarkPrefix => '✓ ';

  @override
  String get gui_cleanup_confirmTitle => 'Delete segment files?';

  @override
  String get gui_cleanup_confirmMessage =>
      'This deletes the per-segment audio clips. The combined track and the manifest are kept. Deleted segments can\'t be reused by --resume, so a re-run narrates them again.';

  @override
  String get gui_cleanup_cancel => 'Cancel';

  @override
  String get gui_cleanup_delete => 'Delete';

  @override
  String get gui_cleanup_ok => 'OK';

  @override
  String get gui_cleanup_deletedTitle => 'Segments deleted';

  @override
  String gui_cleanup_removedMessage(int removedCount, String fileLabel) {
    return 'Removed $removedCount segment $fileLabel.';
  }

  @override
  String get gui_cleanup_cleanupFailedTitle => 'Cleanup failed';

  @override
  String get gui_bootstrap_downloadTitle => 'Download Voice Configurations?';

  @override
  String gui_bootstrap_downloadPrompt(String files) {
    return 'No voice configurations found. Would you like to download starter configurations ($files) from GitHub?';
  }

  @override
  String get gui_bootstrap_notNow => 'Not Now';

  @override
  String get gui_bootstrap_download => 'Download';

  @override
  String get gui_bootstrap_downloading => 'Downloading voice configurations...';

  @override
  String get gui_bootstrap_initializing => 'Initializing...';

  @override
  String get gui_settings_title => 'Settings';

  @override
  String get gui_settings_close => 'Close';

  @override
  String get gui_settings_revealFolder => 'Reveal Config Folder';

  @override
  String get gui_settings_revealFolderTooltip =>
      'Open the voice config directory in the file manager';

  @override
  String get gui_settings_warningsTitle => 'Config warnings';

  @override
  String get gui_settings_noModels =>
      'No models configured. Download the starter configurations to begin.';

  @override
  String get gui_settings_modelsTitle => 'Models';

  @override
  String get gui_settings_editedBadgeTooltip =>
      'This model has a local override in the user folder';

  @override
  String get gui_settings_fieldModelId => 'Model ID';

  @override
  String get gui_settings_fieldProvider => 'Provider';

  @override
  String get gui_settings_fieldFormat => 'Format';

  @override
  String gui_settings_voicesUnreadableTitle(String alias) {
    return 'Cannot read the voice list for $alias';
  }

  @override
  String get gui_settings_voicesUnreadableRevert =>
      'Revert to Downloaded discards this file and restores the downloaded one.';

  @override
  String gui_settings_voicesLockedCaption(String alias) {
    return 'This model\'s voice list is fixed. Add a models/$alias.json file in the user folder to override it.';
  }

  @override
  String get gui_settings_columnLabel => 'Label';

  @override
  String get gui_settings_columnId => 'Voice ID';

  @override
  String get gui_settings_columnGender => 'Gender';

  @override
  String get gui_settings_addVoice => 'Add Voice';

  @override
  String get gui_settings_editVoice => 'Edit Voice';

  @override
  String get gui_settings_removeVoice => 'Remove';

  @override
  String get gui_settings_setDefault => 'Set as default';

  @override
  String get gui_settings_isDefault => 'Default';

  @override
  String get gui_settings_revert => 'Revert to Downloaded';

  @override
  String get gui_settings_revertTooltip =>
      'Discard the local override for this model';

  @override
  String get gui_settings_genderAny => 'Not set';

  @override
  String get gui_settings_genderMale => 'Male';

  @override
  String get gui_settings_genderFemale => 'Female';

  @override
  String get gui_settings_genderNeutral => 'Neutral';

  @override
  String get gui_settings_voiceDialogAddTitle => 'Add voice';

  @override
  String get gui_settings_voiceDialogEditTitle => 'Edit voice';

  @override
  String get gui_settings_voiceDialogLabel => 'Label';

  @override
  String get gui_settings_voiceDialogLabelHint => 'Shown in the voice picker';

  @override
  String get gui_settings_voiceDialogId => 'Voice ID';

  @override
  String get gui_settings_voiceDialogIdHint =>
      'Sent to the provider, e.g. a 32-character id';

  @override
  String get gui_settings_voiceDialogSave => 'Save';

  @override
  String get gui_settings_voiceDialogCancel => 'Cancel';
}
