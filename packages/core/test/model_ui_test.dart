import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'support/fake_provider.dart';

void main() {
  group('ModelUiSpec', () {
    test('is empty until a control is declared', () {
      expect(const ModelUiSpec().isEmpty, isTrue);
      expect(const ModelUiSpec.empty().isEmpty, isTrue);

      const spec = ModelUiSpec([
        ModelUiControl(key: 'accent', label: 'Accent'),
        ModelUiControl(key: 'style', label: 'Style'),
      ]);
      expect(spec.isEmpty, isFalse);
      // Order is the declaration order: the panel renders the controls as given.
      expect(spec.options.map((o) => o.key), ['accent', 'style']);
    });
  });

  group('ModelUiSpec.forProfile', () {
    const plain = TtsModelProfile(
      alias: 'plain',
      id: 'provider/plain-tts',
      formats: [TtsAudioFormat.wav],
      provider: testProvider,
    );
    const styled = TtsModelProfile(
      alias: 'fancy',
      id: 'provider/styled-tts',
      formats: [TtsAudioFormat.wav],
      promptStyle: true,
      provider: testProvider,
    );
    const fast = TtsModelProfile(
      alias: 'fast',
      id: 'provider/fast-tts',
      formats: [TtsAudioFormat.wav],
      supportsSpeed: true,
      provider: testProvider,
    );

    test('a model declaring neither capability gets no controls', () {
      expect(ModelUiSpec.forProfile(plain).isEmpty, isTrue);
    });

    test('promptStyle yields the style controls in order', () {
      final spec = ModelUiSpec.forProfile(styled);
      expect(spec.isEmpty, isFalse);
      expect(spec.options.map((o) => o.key), [
        'gender',
        'accent',
        'style',
        'passagePrefix',
      ]);
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
          formats: [TtsAudioFormat.wav],
          promptStyle: true,
          supportsSpeed: true,
          provider: testProvider,
        ),
      );
      expect(spec.options.map((o) => o.key), [
        'gender',
        'accent',
        'style',
        'passagePrefix',
        'speed',
      ]);
    });

    test('sendsInstructField yields a multiline voice design box', () {
      final spec = ModelUiSpec.forProfile(
        const TtsModelProfile(
          alias: 'designer',
          id: 'provider/voice-design-tts',
          formats: [TtsAudioFormat.wav],
          sendsInstructField: true,
          provider: testProvider,
        ),
      );
      expect(spec.options.map((o) => o.key), ['instruct']);
      expect(spec.options.single.type, ModelUiOptionType.multiline);
    });

    test(
      'instruct comes after the speed slider, and neither implies the other',
      () {
        // A voice design model is fast but has no accent/style pair to speak
        // aloud, so the two option sets must stay independent.
        final spec = ModelUiSpec.forProfile(
          const TtsModelProfile(
            alias: 'designer-fast',
            id: 'provider/voice-design-fast-tts',
            formats: [TtsAudioFormat.wav],
            sendsInstructField: true,
            supportsSpeed: true,
            provider: testProvider,
          ),
        );
        expect(spec.options.map((o) => o.key), ['speed', 'instruct']);
      },
    );
  });
}
