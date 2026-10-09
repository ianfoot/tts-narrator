/// English-only defaults and templates for the narration prompt.
///
/// These strings are instructions addressed to the TTS model, not user-facing
/// interface copy: localizing them changes what the model hears rather than
/// what the user reads. They deliberately live outside any l10n system
/// (`package:flutter_gen` / ARB) and must never be added to one.
///
/// The narrator-gender rewrite is the sharpest edge here:
/// [SettingsController.applyNarratorGender] detects a gendered prefix by literal
/// substring match against [femalePhrase] and [malePhrase], which overlap because
/// `female narrator` contains `male narrator`, so the rewrite special-cases it.
/// Changing the wording of any of those three without updating that match breaks
/// gender switching silently, so [assertPrefixCarriesGender] guards it in tests.
abstract final class PromptDefaults {
  /// Default accent description folded into every prompt.
  static const accent = 'southern British English, neutral and clear';

  /// Default style/register description folded into every prompt.
  static const style = 'warm, composed, restrained, literary';

  /// Default preamble pooled in front of every paragraph.
  ///
  /// Carries [femalePhrase] so the default is gendered; the GUI swaps in
  /// [malePhrase] for a male voice.
  static const passagePrefix =
      'Narrate this passage for an audiobook. '
      'You are a warm, composed female narrator.';

  /// The female narrator form. Note this is a *superstring* of [malePhrase].
  static const femalePhrase = 'female narrator';

  /// The male narrator form.
  static const malePhrase = 'male narrator';

  /// Default minimum words per segment, mirroring the run-setup panel slider
  /// range of 10-100.
  static const minWords = 30;

  /// The ` Accent: <accent>.` fragment, trimmed.
  static String accentSentence(String accent) => ' Accent: ${accent.trim()}.';

  /// The ` Style: <style>.` fragment, trimmed.
  static String styleSentence(String style) => ' Style: ${style.trim()}.';

  /// Bridges the prompt preamble and the passage itself.
  static const readInstruction = ' Read the story exactly as written: ';

  /// Whether [prefix] is recognized as gendered, i.e. contains either phrase.
  ///
  /// A prefix mentioning neither is deliberately left alone by the gender rewrite.
  static bool prefixCarriesGender(String prefix) =>
      prefix.contains(femalePhrase) || prefix.contains(malePhrase);

  /// Debug-only guard for the substring coupling described on [PromptDefaults].
  ///
  /// Call this from tests to catch an edit to [passagePrefix] that would
  /// disable narrator-gender switching.
  static void assertPrefixCarriesGender() {
    assert(
      prefixCarriesGender(passagePrefix),
      'PromptDefaults.passagePrefix no longer contains '
      'femalePhrase/malePhrase, so SettingsController.applyNarratorGender '
      'will silently stop switching narrator gender.',
    );
  }
}
