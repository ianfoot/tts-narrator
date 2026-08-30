import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/config.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';
import 'package:tts_narrator_core/src/narration/prompt.dart';

const _gemini = TtsModelProfile(
  alias: 'gemini',
  id: 'google/gemini-3.1-flash-tts-preview',
  format: 'pcm',
  sampleRate: 24000,
  promptStyle: true,
);

void main() {
  const prefix = 'Narrate this passage for an audiobook.';

  NarrationConfig cfg({bool tags = false, String accent = 'RP', String style = 'warm', String? customPrefix}) =>
      NarrationConfig(
        inputPath: 'story.txt',
        profile: _gemini,
        voice: 'Callirrhoe',
        useCalmTag: tags,
        accent: accent,
        style: style,
        passagePrefix: customPrefix ?? prefix,
      );

  test('wraps passage with prefix, accent, style and read directive', () {
    final p = buildPrompt(cfg(), 'The text.');
    expect(p, contains('Narrate this passage for an audiobook.'));
    expect(p, contains('Accent: RP.'));
    expect(p, contains('Style: warm.'));
    expect(p, contains('Read the story exactly as written: The text.'));
  });

  test('prepends [calm] when tags enabled', () {
    final p = buildPrompt(cfg(tags: true), 'X.');
    expect(p, startsWith('[calm] '));
    expect(buildPrompt(cfg(tags: false), 'X.'), isNot(startsWith('[calm]')));
  });

  test('respects a custom passage prefix', () {
    final p = buildPrompt(cfg(customPrefix: 'Speak softly.'), 'X.');
    expect(p, startsWith('Speak softly.'));
    expect(p, isNot(contains('Narrate this passage')));
  });

  test('trims surrounding whitespace from prefix and accent', () {
    final p = buildPrompt(
      NarrationConfig(
        inputPath: 's',
        profile: _gemini,
        voice: 'v',
        passagePrefix: '  Loop.  ',
        accent: '  RP  ',
        style: ' warm ',
      ),
      'T.',
    );
    expect(p, contains('Loop. Accent: RP.'));
    expect(p, contains('Style: warm.'));
    expect(p.trim(), p);
  });

  test('includes the exact passage content', () {
    final p = buildPrompt(cfg(), 'Multi\nline\npassage.');
    expect(p, contains('Multi\nline\npassage.'));
  });
}