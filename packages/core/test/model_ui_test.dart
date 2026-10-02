import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

void main() {
  group('ModelUiSpec', () {
    test('defaults to empty', () {
      expect(const ModelUiSpec().isEmpty, isTrue);
      expect(const ModelUiSpec.empty().isEmpty, isTrue);
    });

    test('carries declared options in order', () {
      const spec = ModelUiSpec([
        ModelUiControl(key: 'accent', label: 'Accent'),
        ModelUiControl(key: 'style', label: 'Style'),
      ]);
      expect(spec.isEmpty, isFalse);
      expect(spec.options.map((o) => o.key), ['accent', 'style']);
    });
  });

  group('ModelUiSpec.forProfile', () {
    const plain = TtsModelProfile(alias: 'plain', id: 'provider/plain-tts');
    const styled = TtsModelProfile(
      alias: 'fancy',
      id: 'provider/styled-tts',
      promptStyle: true,
    );
    const fast = TtsModelProfile(
      alias: 'fast',
      id: 'provider/fast-tts',
      supportsSpeed: true,
    );

    test('a model declaring neither capability gets no controls', () {
      expect(ModelUiSpec.forProfile(plain).isEmpty, isTrue);
    });

    test('promptStyle yields the style controls in order', () {
      final spec = ModelUiSpec.forProfile(styled);
      expect(spec.isEmpty, isFalse);
      expect(
        spec.options.map((o) => o.key),
        ['gender', 'accent', 'style', 'passagePrefix'],
      );
    });

    test('supportsSpeed yields the speed slider', () {
      final spec = ModelUiSpec.forProfile(fast);
      expect(spec.options.map((o) => o.key), ['speed']);
      expect(spec.options.single.type, ModelUiOptionType.speed);
    });

    test('both capabilities combine, speed last', () {
      final spec = ModelUiSpec.forProfile(
        const TtsModelProfile(
          alias: 'fancy-fast',
          id: 'provider/fancy-fast-tts',
          promptStyle: true,
          supportsSpeed: true,
        ),
      );
      expect(
        spec.options.map((o) => o.key),
        ['gender', 'accent', 'style', 'passagePrefix', 'speed'],
      );
    });
  });
}
