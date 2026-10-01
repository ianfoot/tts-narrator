import 'config.dart';
import 'prompt_strings.dart';

/// Builds the narration prompt for a single paragraph.
///
/// The wording is English-only by design — these are instructions for the TTS
/// model, not UI copy. See [PromptDefaults].
String buildPrompt(NarrationConfig config, String passage) {
  final buffer = StringBuffer();

  buffer.write(config.passagePrefix.trim());
  buffer.write(PromptDefaults.accentSentence(config.accent));
  buffer.write(PromptDefaults.styleSentence(config.style));
  buffer.write(PromptDefaults.readInstruction);
  buffer.write(passage);

  return buffer.toString().trim();
}