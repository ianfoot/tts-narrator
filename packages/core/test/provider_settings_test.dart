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

  // `isEnvReference` and `envRefName` are two readings of the same
  // `^\$\{(\w+)\}$` match, so both are pinned from one table: a bare variable
  // name, or a name with anything wrapped around it, is a literal that would
  // be sent verbatim as the token.
  const refs = <(String, bool, String?)>[
    (r'${VENDOR_API_KEY}', true, 'VENDOR_API_KEY'),
    ('sk-literal', false, null),
    ('VENDOR_API_KEY', false, null),
    (r'$VENDOR_API_KEY', false, null),
    (r'${}', false, null),
    (r'sk-${x}', false, null),
    (r'prefix ${NAME}', false, null),
  ];

  group('isEnvReference', () {
    for (final (input, isRef, _) in refs) {
      test('$input is${isRef ? '' : ' not'} a reference', () {
        expect(isEnvReference(input), isRef);
      });
    }
  });

  group('envRefName', () {
    for (final (input, _, refName) in refs) {
      test('$input names ${refName ?? 'nothing'}', () {
        expect(envRefName(input), refName);
      });
    }
  });
}
