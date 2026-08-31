import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/abort.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';
import 'package:tts_narrator_core/src/narration/model_ui.dart';
import 'package:tts_narrator_core/src/narration/tts_provider.dart';

class _FakeProvider implements TtsProvider {
  const _FakeProvider(this.id, this.name);

  @override
  final String id;

  @override
  final String name;

  @override
  ModelUiSpec modelUiSpecFor(TtsModelProfile model) =>
      const ModelUiSpec.empty();

  @override
  Future<ProviderAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
    AbortToken? abort,
  }) async {
    abort?.throwIfCancelled();
    return ProviderAudio(bytes: input.codeUnits);
  }
}

const _alpha = _FakeProvider('alpha', 'Alpha TTS');
const _beta = _FakeProvider('beta', 'Beta TTS');

void main() {
  group('TtsProviderRegistry', () {
    test('register + resolve returns a provider from the factory', () {
      final registry = TtsProviderRegistry();
      registry.register('alpha', () => _alpha);
      final provider = registry.resolve('alpha');
      expect(provider.id, 'alpha');
      expect(provider.name, 'Alpha TTS');
    });

    test('resolve invokes the factory each time', () {
      final registry = TtsProviderRegistry();
      var calls = 0;
      registry.register('counted', () {
        calls++;
        return _alpha;
      });
      registry.resolve('counted');
      registry.resolve('counted');
      expect(calls, 2);
    });

    test('register replaces a previous registration by id', () {
      final registry = TtsProviderRegistry()..register('alpha', () => _alpha);
      registry.register('alpha', () => _beta);
      expect(registry.resolve('alpha').id, 'beta');
    });

    test('resolveOrNull returns null for an unregistered id', () {
      final registry = TtsProviderRegistry();
      expect(registry.resolveOrNull('nope'), isNull);
    });

    test('resolveOrNull returns the provider for a registered id', () {
      final registry = TtsProviderRegistry()..register('beta', () => _beta);
      expect(registry.resolveOrNull('beta'), isNotNull);
    });

    test('resolve throws for an unknown id, naming it and the registered set', () {
      final registry = TtsProviderRegistry()
        ..register('alpha', () => _alpha)
        ..register('beta', () => _beta);
      expect(
        () => registry.resolve('gamma'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('"gamma"'),
              contains('alpha'),
              contains('beta'),
            ),
          ),
        ),
      );
    });

    test('resolve lists only registered ids (none when empty)', () {
      final registry = TtsProviderRegistry();
      expect(
        () => registry.resolve('x'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('(none)'))),
      );
    });
  });

  group('resolveSettings', () {
    test(r'${ENV} references resolve from the env map', () {
      final out = resolveSettings(
        {'OPENROUTER_API_KEY': r'${OPENROUTER_API_KEY}'},
        env: {'OPENROUTER_API_KEY': 'sk-secret'},
      );
      expect(out['OPENROUTER_API_KEY'], 'sk-secret');
    });

    test('literal values pass through untouched', () {
      final out = resolveSettings(
        {'api_key': 'sk-literal', 'model': 'fish'},
        env: const {},
      );
      expect(out, {'api_key': 'sk-literal', 'model': 'fish'});
    });

    test(r'a missing env var throws naming the variable', () {
      expect(
        () => resolveSettings(
          {'api_key': r'${MISSING_VAR}'},
          env: const {},
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('MISSING_VAR')),
        ),
      );
    });

    test(r'no env map defaults to empty (refs fail loudly, literals pass)', () {
      final out = resolveSettings({'api_key': 'literal'});
      expect(out['api_key'], 'literal');
      expect(
        () => resolveSettings({'k': r'${NOPE}'}),
        throwsA(isA<StateError>()),
      );
    });

    test('an empty env value counts as missing', () {
      expect(
        () => resolveSettings(
          {'api_key': r'${EMPTY_VAR}'},
          env: {'EMPTY_VAR': ''},
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('EMPTY_VAR'))),
      );
      expect(
        () => resolveSettings(
          {'api_key': r'${WS_VAR}'},
          env: {'WS_VAR': '   '},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('non-dollar values (even awkward ones) are untouched', () {
      const raw = <String, String>{
        'api_key': r'sk-${not-a-ref',
        'voice': 'a{b}c',
        'format': 'mp3',
      };
      expect(resolveSettings(raw, env: const {}), raw);
    });

    test('mixed settings resolve independently', () {
      final out = resolveSettings(
        {
          'uri': 'wss://example.invalid',
          'token': r'${TOKEN}',
          'region': 'us-central1',
        },
        env: {'TOKEN': 't0k3n'},
      );
      expect(out, {
        'uri': 'wss://example.invalid',
        'token': 't0k3n',
        'region': 'us-central1',
      });
    });
  });
}