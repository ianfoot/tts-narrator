import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/cost.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';

void main() {
  group('estimateMinutes', () {
    test('word count over 160 wpm', () {
      expect(estimateMinutes(['one two three four five']), closeTo(5 / 160, 1e-9));
    });

    test('empty chunks estimate zero', () {
      expect(estimateMinutes([]), 0);
    });

    test('handles multiple chunks', () {
      expect(estimateMinutes(['a b c', 'd e f g h i j k l m']), closeTo(13 / 160, 1e-9));
    });
  });

  group('estimateCostUsd', () {
    test('free model costs zero (fish)', () {
      expect(estimateCostUsd(kFishProfile, ['A Shorts Story']), 0);
    });

    test('kokoro bills by character', () {
      expect(estimateCostUsd(kKokoroProfile, ['abc']), closeTo(3 / 1e6 * 0.62, 1e-12));
    });

    test('gemini bills input tokens + estimated output audio', () {
      final cost = estimateCostUsd(kGeminiProfile, ['A Shorts Story']);
      expect(cost, greaterThan(0));

      // Hand-check: 14 chars -> ceil(14/4)=4 input tokens; 3 words / 160 wpm = 0.01875 min
      // = 1.125 s -> *160 tok/s = 180 audio tokens.
      expect(cost, closeTo(4 / 1e6 * 1.0 + 180 / 1e6 * 20.0, 1e-9));
    });

    test('larger input scales cost', () {
      final chunks = List.generate(10, (i) => 'Wordy paragraph number $i here.');
      expect(estimateCostUsd(kGeminiProfile, chunks),
          greaterThan(estimateCostUsd(kGeminiProfile, ['A'])));
    });
  });

  group('formatCostUsd', () {
    test(r'free reads $0.00 (free)', () {
      expect(formatCostUsd(0), r'$0.00 (free)');
    });

    test('formats small costs to two decimals', () {
      expect(formatCostUsd(2.406), r'$2.41');
      expect(formatCostUsd(0.004), r'$0.00');
      expect(formatCostUsd(1.0), r'$1.00');
    });
  });
}