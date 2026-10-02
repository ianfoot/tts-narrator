import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/provider_settings.dart';

void main() {
  group('resolveSettings', () {
    test(r'${ENV} references resolve from the env map', () {
      final out = resolveSettings(
        {'VENDOR_API_KEY': r'${VENDOR_API_KEY}'},
        env: {'VENDOR_API_KEY': 'sk-secret'},
      );
      expect(out['VENDOR_API_KEY'], 'sk-secret');
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

  group('resolveProviderApiKey', () {
    test('an api_key literal is the credential', () {
      expect(
        resolveProviderApiKey({
          'api_key': 'sk-literal',
          'base_url': 'https://x',
        }, env: const {}),
        'sk-literal',
      );
    });

    test(r'a ${ENV} reference names the variable to read', () {
      // The shipped provider block shape.
      expect(
        resolveProviderApiKey(
          const {'api_key': r'${VENDOR_API_KEY}'},
          env: const {'VENDOR_API_KEY': 'sk-from-env'},
        ),
        'sk-from-env',
      );
    });

    test('a literal needs no environment', () {
      expect(
        resolveProviderApiKey(const {'api_key': 'sk-literal'}, env: const {}),
        'sk-literal',
      );
    });

    test('an already-expanded \${ENV} value in api_key is passed through', () {
      expect(
        resolveProviderApiKey({'api_key': 'sk-expanded'}, env: const {}),
        'sk-expanded',
      );
    });

    test('a block with no credential setting is keyless', () {
      expect(
        resolveProviderApiKey(
          const {'base_url': 'http://localhost:8000/v1', 'default_voice': 'a'},
          env: const {'VENDOR_API_KEY': 'sk-from-env'},
        ),
        isNull,
      );
    });

    test(
      r'an unset ${ENV} variable resolves to null, not to the reference',
      () {
        expect(
          resolveProviderApiKey(const {
            'api_key': r'${VENDOR_API_KEY}',
          }, env: const {}),
          isNull,
        );
      },
    );

    test('empty and whitespace-only values count as missing', () {
      for (final settings in const [
        {'api_key': ''},
        {'api_key': '   '},
      ]) {
        expect(
          resolveProviderApiKey(settings, env: const {'EMPTY_NAME': ''}),
          isNull,
          reason: '$settings must yield no key',
        );
      }
    });

    test('values are trimmed', () {
      expect(
        resolveProviderApiKey(const {
          'api_key': '  sk-padded  ',
        }, env: const {}),
        'sk-padded',
      );
      // Outer padding is trimmed before the reference is matched.
      expect(
        resolveProviderApiKey(
          const {'api_key': r'  ${VARNAME}  '},
          env: const {'VARNAME': ' sk-env  '},
        ),
        'sk-env',
      );
    });

    test('padding *inside* the braces is not a reference', () {
      // `\w+` admits no spaces, so this is a literal and would be sent verbatim
      // as the token. Pinned because it is a typo that fails at the server
      // rather than here, and the user should not expect a silent fix.
      expect(isEnvReference(r'${ VAR }'), isFalse);
      expect(
        resolveProviderApiKey(
          const {'api_key': r'${ VAR }'},
          env: const {'VAR': 'sk-env'},
        ),
        r'${ VAR }',
      );
    });
  });

  group('isEnvReference', () {
    test(r'a ${NAME} ref is recognised', () {
      expect(isEnvReference(r'${VENDOR_API_KEY}'), isTrue);
    });

    test('a literal, an unwrapped name, and near-misses are not', () {
      expect(isEnvReference('sk-literal'), isFalse);
      // A variable name without the `${}` braces would be sent as a literal
      // token, so this must NOT count as a reference.
      expect(isEnvReference('VENDOR_API_KEY'), isFalse);
      expect(isEnvReference(r'$VENDOR_API_KEY'), isFalse);
      expect(isEnvReference(r'${}'), isFalse);
      expect(isEnvReference(r'sk-${x}'), isFalse);
      expect(isEnvReference(r'prefix ${NAME}'), isFalse);
    });
  });

  group('envRefName', () {
    test('names the variable a ref points at', () {
      expect(envRefName(r'${VENDOR_API_KEY}'), 'VENDOR_API_KEY');
    });

    test('is null for a literal or a malformed reference', () {
      expect(envRefName('sk-literal'), isNull);
      expect(envRefName('VENDOR_API_KEY'), isNull);
      expect(envRefName(r'${}'), isNull);
    });
  });
}
