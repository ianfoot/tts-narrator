// Localized labels for controller-produced *data*.
//
// The controllers (`SettingsController`, `RunController`, `DocumentController`)
// deliberately return enums and nullable fields rather than pre-formatted
// sentences: they are `ChangeNotifier`s with no `BuildContext`, so they cannot
// reach `AppLocalizations`. This file is the other half of that contract — the
// widget layer hands these extensions an `AppLocalizations` and gets text back.
//
// Each extension lives beside the data it renders. If you find yourself wanting
// to add a getter to a controller that returns a `String` for display, add an
// extension here instead.

import '../../../l10n/app_localizations.dart';
import 'controller_errors.dart';
import 'document_controller.dart';
import 'run_controller.dart';
import 'settings_controller.dart';

/// Localized text for [ApiKeySource], rendered on the run-setup status line.
extension ApiKeySourceX on ApiKeySource {
  String apiKeyStatusLabel(AppLocalizations l10n) => switch (this) {
    ApiKeySource.keychain => l10n.gui_run_setup_apiKeyStatusKeychain,
    ApiKeySource.config => l10n.gui_run_setup_apiKeyStatusConfig,
    ApiKeySource.environment => l10n.gui_run_setup_apiKeyStatusEnvironment,
    ApiKeySource.missing => l10n.gui_run_setup_apiKeyStatusMissing,
  };
}

/// Localized explanation for why narration cannot start.
extension NarrationBlockReasonX on NarrationBlockReason {
  String message(AppLocalizations l10n) => switch (this) {
    NarrationBlockReason.noModelConfigured =>
      l10n.gui_controller_errors_noModelConfigured,
    NarrationBlockReason.emptyText =>
      l10n.gui_controller_blockReasons_emptyText,
    NarrationBlockReason.emptyVoiceDesign =>
      l10n.gui_controller_blockReasons_emptyVoiceDesign,
    NarrationBlockReason.alreadyRunning =>
      l10n.gui_controller_blockReasons_alreadyRunning,
  };
}

/// The document's display name, falling back to the localized placeholder when
/// it has never been saved.
///
/// Distinct from [untitledDocumentName], which is the on-disk filename.
extension DocumentNameX on String? {
  String display(AppLocalizations l10n) => this ?? l10n.app_untitledDocument;
}

/// Localized message for a controller-thrown exception.
///
/// Controllers throw these untyped of language; call sites that render one pass
/// it here. Anything not recognized falls back to [cause]'s `toString()` so an
/// unexpected value still shows something useful rather than nothing.
extension ControllerErrorMessage on Object {
  String localizedMessage(AppLocalizations l10n) => switch (this) {
    NoModelConfigured() => l10n.gui_controller_errors_noModelConfigured,
    NoVoiceSelected(:final modelAlias) =>
      l10n.gui_controller_errors_noVoiceSelected(modelAlias),
    CannotOpenTextFile() => l10n.gui_controller_errors_cannotOpenTextFile,
    _ => toString(),
  };
}
