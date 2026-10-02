import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/provider_settings.dart';

void main() {
  group('resolveSettings', () {
    test(r'${ENV} references resolve from the env map', () {
      final out = resolveSettings(
        {'OPENROUTER_API_KEY': r'${OPENROUTER_API_KEY}'},
        env: {'OPENROUTER_API_KEY': 'sk-secret'},
      );
      expect(out['OPENROUTER_API_KEY'], 'sk-secret');
    });

    test('literal values pass through untouched', () {
      final out = resolveSettings({
        'api_key': 'sk-literal',
        'model': 'fish',
      }, env: const {});
      expect(out, {'api_key': 'sk-literal', 'model': 'fish'});
    });

    test(r'a missing env var throws naming the variable', () {
      expect(
        () => resolveSettings({'api_key': r'${MISSING_VAR}'}, env: const {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('MISSING_VAR'),
          ),
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
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('EMPTY_VAR'),
          ),
        ),
      );
      expect(
        () =>
            resolveSettings({'api_key': r'${WS_VAR}'}, env: {'WS_VAR': '   '}),
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
