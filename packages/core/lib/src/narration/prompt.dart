import 'config.dart';

/// Builds the narration prompt for a single paragraph.
///
/// Template lives here so it can be tuned in one place.
String buildPrompt(NarrationConfig config, String passage) {
  final buffer = StringBuffer();

  buffer.write(config.passagePrefix.trim());
  buffer.write(' Accent: ${config.accent.trim()}.');
  buffer.write(' Style: ${config.style.trim()}.');
  buffer.write(' Read the story exactly as written: ');
  buffer.write(passage);

  return buffer.toString().trim();
}
