import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/l10n_labels.dart';

import '../support/l10n_test_support.dart';

void main() {
  group('CostUsdX.costLabel', () {
    test('annotates a zero estimate as free', () {
      expect(0.0.costLabel(testL10n), r'$0.00 (free)');
    });

    test('leaves a paid estimate as the bare amount', () {
      expect(2.406.costLabel(testL10n), r'$2.41');
      expect(1.0.costLabel(testL10n), r'$1.00');
    });

    test('treats a sub-cent estimate as free, since it rounds to zero', () {
      // Core has already rounded by the time the caller sees the number, so the
      // free annotation has to follow the same zero test or a rounding estimate
      // reads as a price of nothing.
      expect(0.004.costLabel(testL10n), r'$0.00 (free)');
    });

    test('takes the annotation from l10n rather than hardcoding it', () {
      // The point of moving "(free)" out of core: the word is the interface's,
      // and it is read from the ARB so a locale can say it differently.
      expect(0.0.costLabel(testL10n), contains(testL10n.core_costFree));
    });
  });
}
