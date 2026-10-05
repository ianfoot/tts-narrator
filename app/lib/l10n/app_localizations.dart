import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @app_title.
  ///
  /// In en, this message translates to:
  /// **'TTS Narrator'**
  String get app_title;

  /// No description provided for @app_untitledDocument.
  ///
  /// In en, this message translates to:
  /// **'untitled.txt'**
  String get app_untitledDocument;

  /// No description provided for @app_fileTypeGroup.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get app_fileTypeGroup;

  /// Segment count noun; used in the editor status bar and the narration summary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{segment} other{segments}}'**
  String core_plurals_segment(int count);

  /// Word count noun; used under each narration segment.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{word} other{words}}'**
  String core_plurals_word(int count);

  /// Minute count noun; used in the editor status bar estimate.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{min} other{mins}}'**
  String core_plurals_minute(int count);

  /// Character count noun; used in the editor status bar.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{character} other{characters}}'**
  String core_plurals_character(int count);

  /// File count noun; used in the segment-cleanup confirmation.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{file} other{files}}'**
  String core_plurals_file(int count);

  /// No description provided for @gui_controller_errors_noModelConfigured.
  ///
  /// In en, this message translates to:
  /// **'No voice model is configured. Download the starter configs, or add model files to the voice config directory.'**
  String get gui_controller_errors_noModelConfigured;

  /// Raised when the active model has neither a selected nor a default voice.
  ///
  /// In en, this message translates to:
  /// **'No voice selected for \"{modelAlias}\" — pick an alias or set a default in the voice config.'**
  String gui_controller_errors_noVoiceSelected(String modelAlias);

  /// No description provided for @gui_controller_errors_cannotOpenTextFile.
  ///
  /// In en, this message translates to:
  /// **'Cannot open text file'**
  String get gui_controller_errors_cannotOpenTextFile;

  /// No description provided for @gui_controller_blockReasons_emptyText.
  ///
  /// In en, this message translates to:
  /// **'Editor text is empty'**
  String get gui_controller_blockReasons_emptyText;

  /// No description provided for @gui_controller_blockReasons_alreadyRunning.
  ///
  /// In en, this message translates to:
  /// **'Narration is already running.'**
  String get gui_controller_blockReasons_alreadyRunning;

  /// No description provided for @gui_editor_toolbar_narrate.
  ///
  /// In en, this message translates to:
  /// **'Narrate'**
  String get gui_editor_toolbar_narrate;

  /// No description provided for @gui_editor_toolbar_playFull.
  ///
  /// In en, this message translates to:
  /// **'Play Full'**
  String get gui_editor_toolbar_playFull;

  /// No description provided for @gui_editor_toolbar_stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get gui_editor_toolbar_stop;

  /// Tooltip on the theme-mode button.
  ///
  /// In en, this message translates to:
  /// **'Appearance: {mode}'**
  String gui_editor_toolbar_appearanceTooltip(String mode);

  /// No description provided for @gui_editor_toolbar_showHideSettings.
  ///
  /// In en, this message translates to:
  /// **'Show / hide settings'**
  String get gui_editor_toolbar_showHideSettings;

  /// No description provided for @gui_editor_toolbar_setOutputFolder.
  ///
  /// In en, this message translates to:
  /// **'Set output folder'**
  String get gui_editor_toolbar_setOutputFolder;

  /// No description provided for @gui_editor_toolbar_openTextFile.
  ///
  /// In en, this message translates to:
  /// **'Open text file'**
  String get gui_editor_toolbar_openTextFile;

  /// No description provided for @gui_editor_toolbar_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get gui_editor_toolbar_save;

  /// No description provided for @gui_editor_toolbar_cleanupSegments.
  ///
  /// In en, this message translates to:
  /// **'Clean up segments'**
  String get gui_editor_toolbar_cleanupSegments;

  /// No description provided for @gui_editor_toolbar_themeModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get gui_editor_toolbar_themeModeAuto;

  /// No description provided for @gui_editor_toolbar_themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get gui_editor_toolbar_themeModeLight;

  /// No description provided for @gui_editor_toolbar_themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get gui_editor_toolbar_themeModeDark;

  /// No description provided for @gui_editor_hintText.
  ///
  /// In en, this message translates to:
  /// **'Type, paste text, or open a .txt file...'**
  String get gui_editor_hintText;

  /// Tooltip shown when narration is blocked; {message} is the localized block reason.
  ///
  /// In en, this message translates to:
  /// **'Cannot narrate: {message}'**
  String gui_editor_cannotNarratePrefix(String message);

  /// Word and character count under the editor. {words}/{chars} are pre-formatted for the active locale (grouping separators); {wordLabel}/{charLabel} are localized plurals.
  ///
  /// In en, this message translates to:
  /// **'{words} {wordLabel} · {chars} {charLabel}'**
  String gui_editor_statusBar_wordCharCount(
    String words,
    String wordLabel,
    String chars,
    String charLabel,
  );

  /// Live estimate under the editor. {minutes} is a locale-formatted number; {minuteLabel} is a localized plural of 'minute'.
  ///
  /// In en, this message translates to:
  /// **'{segments} {segmentLabel} · ~{minutes} {minuteLabel} · ~{cost} est.'**
  String gui_editor_statusBar_estimate(
    int segments,
    String segmentLabel,
    String minutes,
    String minuteLabel,
    String cost,
  );

  /// No description provided for @gui_settings_header.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get gui_settings_header;

  /// No description provided for @gui_settings_modelVoiceSection.
  ///
  /// In en, this message translates to:
  /// **'Model & voice'**
  String get gui_settings_modelVoiceSection;

  /// No description provided for @gui_settings_modelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get gui_settings_modelLabel;

  /// No description provided for @gui_settings_voiceAliasLabel.
  ///
  /// In en, this message translates to:
  /// **'Voice alias'**
  String get gui_settings_voiceAliasLabel;

  /// No description provided for @gui_settings_advancedVoiceId.
  ///
  /// In en, this message translates to:
  /// **'Advanced Voice ID'**
  String get gui_settings_advancedVoiceId;

  /// No description provided for @gui_settings_overridesSelectedAlias.
  ///
  /// In en, this message translates to:
  /// **'Overrides selected alias'**
  String get gui_settings_overridesSelectedAlias;

  /// No description provided for @gui_settings_freeFormVoiceHint.
  ///
  /// In en, this message translates to:
  /// **'free-form id or provider voice'**
  String get gui_settings_freeFormVoiceHint;

  /// No description provided for @gui_settings_selectVoiceHint.
  ///
  /// In en, this message translates to:
  /// **'Select a Voice...'**
  String get gui_settings_selectVoiceHint;

  /// No description provided for @gui_settings_languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get gui_settings_languageLabel;

  /// No description provided for @gui_settings_selectLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Select a Language...'**
  String get gui_settings_selectLanguageHint;

  /// No description provided for @gui_settings_genderAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get gui_settings_genderAny;

  /// No description provided for @gui_settings_genderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get gui_settings_genderFemale;

  /// No description provided for @gui_settings_genderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get gui_settings_genderMale;

  /// No description provided for @gui_settings_modelOptionsSection.
  ///
  /// In en, this message translates to:
  /// **'Model options'**
  String get gui_settings_modelOptionsSection;

  /// No description provided for @gui_settings_speedLabel.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get gui_settings_speedLabel;

  /// No description provided for @gui_settings_speedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Speech rate multiplier (1.0 = normal)'**
  String get gui_settings_speedTooltip;

  /// No description provided for @gui_settings_runSection.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get gui_settings_runSection;

  /// No description provided for @gui_settings_sendWholeFile.
  ///
  /// In en, this message translates to:
  /// **'Send whole file'**
  String get gui_settings_sendWholeFile;

  /// No description provided for @gui_settings_minWordsLabel.
  ///
  /// In en, this message translates to:
  /// **'Min words per segment'**
  String get gui_settings_minWordsLabel;

  /// No description provided for @gui_settings_sampleMode.
  ///
  /// In en, this message translates to:
  /// **'Sample mode'**
  String get gui_settings_sampleMode;

  /// No description provided for @gui_settings_narrateFirstSegments.
  ///
  /// In en, this message translates to:
  /// **'Narrate first segments only'**
  String get gui_settings_narrateFirstSegments;

  /// No description provided for @gui_settings_skipCompletedSegments.
  ///
  /// In en, this message translates to:
  /// **'Skip completed segments (Resume)'**
  String get gui_settings_skipCompletedSegments;

  /// Model dropdown label when a profile has no display name.
  ///
  /// In en, this message translates to:
  /// **'{alias} — {id}'**
  String gui_settings_modelDisplayFallback(String alias, String id);

  /// No description provided for @gui_settings_apiKeySection.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get gui_settings_apiKeySection;

  /// No description provided for @gui_settings_apiKeySectionTooltip.
  ///
  /// In en, this message translates to:
  /// **'API key for the narration provider'**
  String get gui_settings_apiKeySectionTooltip;

  /// No description provided for @gui_settings_apiKeyStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Key source'**
  String get gui_settings_apiKeyStatusLabel;

  /// No description provided for @gui_settings_apiKeyStatusKeychain.
  ///
  /// In en, this message translates to:
  /// **'Stored in keychain'**
  String get gui_settings_apiKeyStatusKeychain;

  /// No description provided for @gui_settings_apiKeyStatusConfig.
  ///
  /// In en, this message translates to:
  /// **'Set in provider config'**
  String get gui_settings_apiKeyStatusConfig;

  /// No description provided for @gui_settings_apiKeyStatusEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Set via environment variable'**
  String get gui_settings_apiKeyStatusEnvironment;

  /// No description provided for @gui_settings_apiKeyStatusMissing.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get gui_settings_apiKeyStatusMissing;

  /// No description provided for @gui_settings_apiKeyFieldPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Paste your API key here'**
  String get gui_settings_apiKeyFieldPlaceholder;

  /// No description provided for @gui_settings_apiKeyFieldTooltip.
  ///
  /// In en, this message translates to:
  /// **'API key, saved to the system keychain'**
  String get gui_settings_apiKeyFieldTooltip;

  /// No description provided for @gui_settings_apiKeySave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get gui_settings_apiKeySave;

  /// No description provided for @gui_settings_apiKeyRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get gui_settings_apiKeyRemove;

  /// No description provided for @gui_settings_apiKeyStoreError.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the system key store.'**
  String get gui_settings_apiKeyStoreError;

  /// No description provided for @gui_settings_modelDropdownTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select the TTS model to use for narration'**
  String get gui_settings_modelDropdownTooltip;

  /// No description provided for @gui_settings_voiceDropdownTooltip.
  ///
  /// In en, this message translates to:
  /// **'Choose voice for current model'**
  String get gui_settings_voiceDropdownTooltip;

  /// No description provided for @gui_settings_sendWholeFileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Generate single audio file instead of segments'**
  String get gui_settings_sendWholeFileTooltip;

  /// No description provided for @gui_settings_sampleModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Generate only first N segments for testing'**
  String get gui_settings_sampleModeTooltip;

  /// No description provided for @gui_settings_resumeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Skip already generated segments when resuming'**
  String get gui_settings_resumeTooltip;

  /// No description provided for @gui_settings_minWordsSliderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Merge paragraphs shorter than this word count'**
  String get gui_settings_minWordsSliderTooltip;

  /// No description provided for @gui_settings_voiceRawFieldTooltip.
  ///
  /// In en, this message translates to:
  /// **'Custom voice ID or provider voice identifier'**
  String get gui_settings_voiceRawFieldTooltip;

  /// No description provided for @gui_settings_accentFieldTooltip.
  ///
  /// In en, this message translates to:
  /// **'Voice accent description (e.g., \'southern British English\')'**
  String get gui_settings_accentFieldTooltip;

  /// No description provided for @gui_settings_styleFieldTooltip.
  ///
  /// In en, this message translates to:
  /// **'Voice style personality (e.g., \'warm, composed\')'**
  String get gui_settings_styleFieldTooltip;

  /// No description provided for @gui_settings_prefixFieldTooltip.
  ///
  /// In en, this message translates to:
  /// **'Text prepended to each paragraph'**
  String get gui_settings_prefixFieldTooltip;

  /// No description provided for @gui_settings_sampleLenFieldTooltip.
  ///
  /// In en, this message translates to:
  /// **'Number of paragraphs to narrate in sample mode'**
  String get gui_settings_sampleLenFieldTooltip;

  /// No description provided for @gui_settings_genderControlTooltip.
  ///
  /// In en, this message translates to:
  /// **'Filter voices by gender'**
  String get gui_settings_genderControlTooltip;

  /// No description provided for @gui_settings_languageDropdownTooltip.
  ///
  /// In en, this message translates to:
  /// **'Language sent to the model (lang_code)'**
  String get gui_settings_languageDropdownTooltip;

  /// No description provided for @gui_settings_advancedVoiceIdTooltip.
  ///
  /// In en, this message translates to:
  /// **'Enter custom voice settings'**
  String get gui_settings_advancedVoiceIdTooltip;

  /// No description provided for @gui_narration_backToEditor.
  ///
  /// In en, this message translates to:
  /// **'Back to editor'**
  String get gui_narration_backToEditor;

  /// Title of the narration screen.
  ///
  /// In en, this message translates to:
  /// **'Narrating: {documentName}'**
  String gui_narration_narratingTitle(String documentName);

  /// Run summary pill above the narration segment list.
  ///
  /// In en, this message translates to:
  /// **'{modelName} · {voice} | {segments} {segmentLabel} · ~{minutes} min · ~{cost}'**
  String gui_narration_summaryPill(
    String modelName,
    String voice,
    int segments,
    String segmentLabel,
    String minutes,
    String cost,
  );

  /// No description provided for @gui_narration_noSegmentsYet.
  ///
  /// In en, this message translates to:
  /// **'No segments yet.'**
  String get gui_narration_noSegmentsYet;

  /// No description provided for @gui_narration_narrationComplete.
  ///
  /// In en, this message translates to:
  /// **'Narration complete.'**
  String get gui_narration_narrationComplete;

  /// No description provided for @gui_narration_narrationStopped.
  ///
  /// In en, this message translates to:
  /// **'Narration was stopped.'**
  String get gui_narration_narrationStopped;

  /// Run failure banner.
  ///
  /// In en, this message translates to:
  /// **'Narration failed: {runError}'**
  String gui_narration_narrationFailed(String runError);

  /// Numbered segment heading in the narration list.
  ///
  /// In en, this message translates to:
  /// **'Segment {segmentNumber}'**
  String gui_narration_segmentLabel(int segmentNumber);

  /// Trailing word count under a segment heading. {words} is the count; {wordLabel} is a localized plural of 'word'.
  ///
  /// In en, this message translates to:
  /// **' · {words} {wordLabel}'**
  String gui_narration_wordCountSuffix(int words, String wordLabel);

  /// No description provided for @gui_narration_processing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get gui_narration_processing;

  /// No description provided for @gui_narration_pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get gui_narration_pending;

  /// No description provided for @gui_narration_play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get gui_narration_play;

  /// No description provided for @gui_narration_stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get gui_narration_stop;

  /// No description provided for @gui_narration_resumedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Resumed — tap to play'**
  String get gui_narration_resumedTooltip;

  /// No description provided for @gui_narration_back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get gui_narration_back;

  /// No description provided for @gui_narration_cancelRun.
  ///
  /// In en, this message translates to:
  /// **'Cancel Run'**
  String get gui_narration_cancelRun;

  /// Title of the dialog guarding against leaving an active run.
  ///
  /// In en, this message translates to:
  /// **'Cancel active narration run?'**
  String get gui_narration_confirmCancelTitle;

  /// Body of the dialog guarding against leaving an active run.
  ///
  /// In en, this message translates to:
  /// **'Generation stops now; completed clips stay playable in this session.'**
  String get gui_narration_confirmCancelMessage;

  /// No description provided for @gui_menu_appMenu.
  ///
  /// In en, this message translates to:
  /// **'TTS Narrator'**
  String get gui_menu_appMenu;

  /// No description provided for @gui_menu_preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences…'**
  String get gui_menu_preferences;

  /// No description provided for @gui_menu_file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get gui_menu_file;

  /// No description provided for @gui_menu_openText.
  ///
  /// In en, this message translates to:
  /// **'Open Text…'**
  String get gui_menu_openText;

  /// No description provided for @gui_menu_outputFolder.
  ///
  /// In en, this message translates to:
  /// **'Output Folder…'**
  String get gui_menu_outputFolder;

  /// No description provided for @gui_menu_narrate.
  ///
  /// In en, this message translates to:
  /// **'Narrate'**
  String get gui_menu_narrate;

  /// File-menu item that empties the editor. Previously hardcoded in both menu bars.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get gui_menu_clear;

  /// No description provided for @gui_menu_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get gui_menu_save;

  /// No description provided for @gui_menu_saveAs.
  ///
  /// In en, this message translates to:
  /// **'Save As…'**
  String get gui_menu_saveAs;

  /// No description provided for @gui_menu_cleanUpSegments.
  ///
  /// In en, this message translates to:
  /// **'Clean Up Segments…'**
  String get gui_menu_cleanUpSegments;

  /// No description provided for @gui_menu_quit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get gui_menu_quit;

  /// No description provided for @gui_menu_edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get gui_menu_edit;

  /// No description provided for @gui_menu_undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get gui_menu_undo;

  /// No description provided for @gui_menu_redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get gui_menu_redo;

  /// No description provided for @gui_menu_cut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get gui_menu_cut;

  /// No description provided for @gui_menu_copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get gui_menu_copy;

  /// No description provided for @gui_menu_paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get gui_menu_paste;

  /// No description provided for @gui_menu_selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get gui_menu_selectAll;

  /// No description provided for @gui_menu_view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get gui_menu_view;

  /// No description provided for @gui_menu_appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get gui_menu_appearance;

  /// No description provided for @gui_menu_themeModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get gui_menu_themeModeAuto;

  /// No description provided for @gui_menu_themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get gui_menu_themeModeLight;

  /// No description provided for @gui_menu_themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get gui_menu_themeModeDark;

  /// No description provided for @gui_menu_toggleSettingsPanel.
  ///
  /// In en, this message translates to:
  /// **'Toggle Settings Panel'**
  String get gui_menu_toggleSettingsPanel;

  /// No description provided for @gui_menu_window.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get gui_menu_window;

  /// No description provided for @gui_menu_checkmarkPrefix.
  ///
  /// In en, this message translates to:
  /// **'✓ '**
  String get gui_menu_checkmarkPrefix;

  /// No description provided for @gui_cleanup_confirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete segment files?'**
  String get gui_cleanup_confirmTitle;

  /// No description provided for @gui_cleanup_confirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This deletes the per-segment audio clips. The combined track and the manifest are kept. Deleted segments can\'t be reused by --resume, so a re-run narrates them again.'**
  String get gui_cleanup_confirmMessage;

  /// No description provided for @gui_cleanup_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gui_cleanup_cancel;

  /// No description provided for @gui_cleanup_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get gui_cleanup_delete;

  /// No description provided for @gui_cleanup_ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get gui_cleanup_ok;

  /// No description provided for @gui_cleanup_deletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Segments deleted'**
  String get gui_cleanup_deletedTitle;

  /// Cleanup result dialog. {fileLabel} is a localized plural of 'file' ('file'/'files').
  ///
  /// In en, this message translates to:
  /// **'Removed {removedCount} segment {fileLabel}.'**
  String gui_cleanup_removedMessage(int removedCount, String fileLabel);

  /// No description provided for @gui_cleanup_cleanupFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cleanup failed'**
  String get gui_cleanup_cleanupFailedTitle;

  /// No description provided for @gui_bootstrap_downloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Download Voice Configurations?'**
  String get gui_bootstrap_downloadTitle;

  /// First-run prompt offering to download starter voice configs.
  ///
  /// In en, this message translates to:
  /// **'No voice configurations found. Would you like to download starter configurations ({files}) from GitHub?'**
  String gui_bootstrap_downloadPrompt(String files);

  /// No description provided for @gui_bootstrap_notNow.
  ///
  /// In en, this message translates to:
  /// **'Not Now'**
  String get gui_bootstrap_notNow;

  /// No description provided for @gui_bootstrap_download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get gui_bootstrap_download;

  /// No description provided for @gui_bootstrap_downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading voice configurations...'**
  String get gui_bootstrap_downloading;

  /// No description provided for @gui_bootstrap_initializing.
  ///
  /// In en, this message translates to:
  /// **'Initializing...'**
  String get gui_bootstrap_initializing;

  /// No description provided for @gui_config_title.
  ///
  /// In en, this message translates to:
  /// **'Providers & Voices'**
  String get gui_config_title;

  /// No description provided for @gui_config_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get gui_config_close;

  /// No description provided for @gui_config_revealFolder.
  ///
  /// In en, this message translates to:
  /// **'Reveal Config Folder'**
  String get gui_config_revealFolder;

  /// No description provided for @gui_config_revealFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open the voice config directory in the file manager'**
  String get gui_config_revealFolderTooltip;

  /// No description provided for @gui_config_warningsTitle.
  ///
  /// In en, this message translates to:
  /// **'Config warnings'**
  String get gui_config_warningsTitle;

  /// No description provided for @gui_config_noModels.
  ///
  /// In en, this message translates to:
  /// **'No models configured. Download the starter configurations to begin.'**
  String get gui_config_noModels;

  /// No description provided for @gui_config_modelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get gui_config_modelsTitle;

  /// No description provided for @gui_config_editedBadgeTooltip.
  ///
  /// In en, this message translates to:
  /// **'This model has a local override in the user folder'**
  String get gui_config_editedBadgeTooltip;

  /// No description provided for @gui_config_fieldModelId.
  ///
  /// In en, this message translates to:
  /// **'Model ID'**
  String get gui_config_fieldModelId;

  /// No description provided for @gui_config_fieldProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get gui_config_fieldProvider;

  /// No description provided for @gui_config_fieldFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get gui_config_fieldFormat;

  /// Title shown in place of a model's voice table when its config file does not parse.
  ///
  /// In en, this message translates to:
  /// **'Cannot read the voice list for {alias}'**
  String gui_config_voicesUnreadableTitle(String alias);

  /// Hint under an unreadable voice table, when a local override can be discarded.
  ///
  /// In en, this message translates to:
  /// **'Revert to Downloaded discards this file and restores the downloaded one.'**
  String get gui_config_voicesUnreadableRevert;

  /// Caption shown under a locked model's read-only voice table.
  ///
  /// In en, this message translates to:
  /// **'This model\'s voice list is fixed. Add a models/{alias}.json file in the user folder to override it.'**
  String gui_config_voicesLockedCaption(String alias);

  /// No description provided for @gui_config_columnLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get gui_config_columnLabel;

  /// No description provided for @gui_config_columnId.
  ///
  /// In en, this message translates to:
  /// **'Voice ID'**
  String get gui_config_columnId;

  /// No description provided for @gui_config_columnGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gui_config_columnGender;

  /// No description provided for @gui_config_addVoice.
  ///
  /// In en, this message translates to:
  /// **'Add Voice'**
  String get gui_config_addVoice;

  /// No description provided for @gui_config_editVoice.
  ///
  /// In en, this message translates to:
  /// **'Edit Voice'**
  String get gui_config_editVoice;

  /// No description provided for @gui_config_removeVoice.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get gui_config_removeVoice;

  /// No description provided for @gui_config_setDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get gui_config_setDefault;

  /// No description provided for @gui_config_isDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get gui_config_isDefault;

  /// No description provided for @gui_config_revert.
  ///
  /// In en, this message translates to:
  /// **'Revert to Downloaded'**
  String get gui_config_revert;

  /// No description provided for @gui_config_revertTooltip.
  ///
  /// In en, this message translates to:
  /// **'Discard the local override for this model'**
  String get gui_config_revertTooltip;

  /// No description provided for @gui_config_genderAny.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get gui_config_genderAny;

  /// No description provided for @gui_config_genderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get gui_config_genderMale;

  /// No description provided for @gui_config_genderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get gui_config_genderFemale;

  /// No description provided for @gui_config_genderNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get gui_config_genderNeutral;

  /// No description provided for @gui_config_voiceDialogAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add voice'**
  String get gui_config_voiceDialogAddTitle;

  /// No description provided for @gui_config_voiceDialogEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit voice'**
  String get gui_config_voiceDialogEditTitle;

  /// No description provided for @gui_config_voiceDialogLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get gui_config_voiceDialogLabel;

  /// No description provided for @gui_config_voiceDialogLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Shown in the voice picker'**
  String get gui_config_voiceDialogLabelHint;

  /// No description provided for @gui_config_voiceDialogId.
  ///
  /// In en, this message translates to:
  /// **'Voice ID'**
  String get gui_config_voiceDialogId;

  /// No description provided for @gui_config_voiceDialogIdHint.
  ///
  /// In en, this message translates to:
  /// **'Sent to the provider, e.g. a 32-character id'**
  String get gui_config_voiceDialogIdHint;

  /// No description provided for @gui_config_voiceDialogSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get gui_config_voiceDialogSave;

  /// No description provided for @gui_config_voiceDialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gui_config_voiceDialogCancel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
