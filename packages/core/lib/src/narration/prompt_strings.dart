/// English-only defaults and templates for the narration prompt.
///
/// These strings are instructions addressed to the TTS model, not user-facing
/// interface copy: localizing them changes what the model hears rather than
/// what the user reads. They deliberately live outside any l10n system
/// (`package:flutter_gen` / ARB) and must never be added to one.
///
/// The narrator-gender rewrite is the sharpest edge here.
/// [SettingsController.applyNarratorGender] detects a gendered prefix by
/// literal substring matching against [femalePhrase] and [malePhrase], and
/// because `female narrator` *contains* `male narrator` as a substring it
/// special-cases the overlap. Changing the wording of [passagePrefix],
/// [femalePhrase], or [malePhrase] without updating that match silently breaks
/// gender switching rather than failing loudly, so [assertPrefixCarriesGender]
/// guards it in tests.
abstract final class PromptDefaults {
  /// Default accent description folded into every prompt.
  static const accent = 'southern British English, neutral and clear';

  /// Default style/register description folded into every prompt.
  static const style = 'warm, composed, restrained, literary';

  /// Default preamble pooled in front of every paragraph.
  ///
  /// Carries [femalePhrase] so the default state is gendered; the GUI swaps it
  /// for [malePhrase] when the user selects a male voice.
  static const passagePrefix =
      'Narrate this passage for an audiobook. '
      'You are a warm, composed female narrator.';

  /// The female narrator form. Note this is a *superstring* of [malePhrase].
  static const femalePhrase = 'female narrator';

  /// The male narrator form.
  static const malePhrase = 'male narrator';

  /// Default minimum words per segment, mirroring the settings-rail slider
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
  /// A custom prefix that mentions neither is left alone by the gender
  /// rewrite, which is intentional.
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
