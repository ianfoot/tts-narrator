/// Typed failures the GUI controllers raise for conditions the user must act
/// on.
///
/// Each carries only the data needed to render its message — never a
/// pre-formatted sentence, for the reason given in `l10n_labels.dart`. The widget
/// layer catches, matches the type, and resolves the text through `l10n`. See
/// `settings_l10n.dart` for the translations.
///
/// Distinct types rather than pre-baked `StateError`/`FormatException` messages,
/// so a catch site can tell "the user needs to pick a model" apart from an
/// unexpected fault without string-matching.
///
/// A missing API key is deliberately absent: whether a run needs one is the
/// server's judgement, so the app never blocks on one. See
/// `SettingsController._resolveApiKey`.
library;

/// The voice config has no usable model profile.
class NoModelConfigured implements Exception {
  const NoModelConfigured();
}

/// The active model has neither a selected voice nor a configured default.
///
/// Carries [modelAlias] so the message can name the model that needs a voice.
class NoVoiceSelected implements Exception {
  const NoVoiceSelected(this.modelAlias);

  /// The model's alias, e.g. `fish`.
  final String modelAlias;

  @override
  String toString() => 'NoVoiceSelected($modelAlias)';
}

/// A `.txt` document could not be opened.
class CannotOpenTextFile implements Exception {
  const CannotOpenTextFile(this.path);

  /// The path that failed to open.
  final String path;

  @override
  String toString() => 'CannotOpenTextFile($path)';
}
