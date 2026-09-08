import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

class _SpecProvider implements TtsProvider {
  @override
  String get id => 'spec';

  @override
  String get name => 'Spec TTS';

  @override
  ModelUiSpec modelUiSpecFor(TtsModelProfile model) =>
      model.promptStyle ? _fancy : const ModelUiSpec.empty();

  static const _fancy = ModelUiSpec([
    ModelUiControl(key: 'accent', label: 'Accent'),
    ModelUiControl(
      key: 'passagePrefix',
      label: 'Passage prefix',
      type: ModelUiOptionType.multiline,
    ),
    ModelUiControl(
      key: 'useCalmTag',
      label: 'Prepend [calm] tag',
      type: ModelUiOptionType.bool,
    ),
  ]);

  @override
  Future<GeneratedAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
    AbortToken? abort,
  }) async => GeneratedAudio(bytes: input.codeUnits);
}

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

  group('TtsProvider.modelUiSpecFor', () {
    const styled = TtsModelProfile(
      alias: 'fancy',
      id: 'provider/styled-tts',
      promptStyle: true,
    );
    const plain = TtsModelProfile(alias: 'plain', id: 'provider/plain-tts');

    test('a provider declares options only for the models it serves', () {
      final provider = _SpecProvider();
      expect(provider.modelUiSpecFor(styled).isEmpty, isFalse);
      expect(provider.modelUiSpecFor(styled).options, hasLength(3));
      expect(provider.modelUiSpecFor(plain).isEmpty, isTrue);
    });
  });
}
