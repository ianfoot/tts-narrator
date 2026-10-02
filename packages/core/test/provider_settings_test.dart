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

  group('resolveProviderApiKey', () {
    test('an api_key literal is the credential', () {
      expect(
        resolveProviderApiKey(
          {'api_key': 'sk-literal', 'base_url': 'https://x'},
          env: const {},
        ),
        'sk-literal',
      );
    });

    test('the apiKey alias is read too', () {
      expect(
        resolveProviderApiKey(
          const {'apiKey': 'sk-alias'},
          env: const {},
        ),
        'sk-alias',
      );
    });

    test('api_key_env holds a variable *name*, resolved from env', () {
      // The shipped provider block shape: a bare name, not `${NAME}`.
      expect(
        resolveProviderApiKey(
          const {'api_key_env': 'OPENROUTER_API_KEY'},
          env: const {'OPENROUTER_API_KEY': 'sk-from-env'},
        ),
        'sk-from-env',
      );
    });

    test('api_key wins over api_key_env', () {
      expect(
        resolveProviderApiKey(
          const {'api_key': 'sk-literal', 'api_key_env': 'OTHER'},
          env: const {'OTHER': 'sk-env'},
        ),
        'sk-literal',
      );
    });

    test('an already-expanded \${ENV} value in api_key is passed through', () {
      expect(
        resolveProviderApiKey(
          {'api_key': 'sk-expanded'},
          env: const {},
        ),
        'sk-expanded',
      );
    });

    test('a block with no credential setting is keyless', () {
      expect(
        resolveProviderApiKey(
          const {'base_url': 'http://localhost:8000/v1', 'default_voice': 'a'},
          env: const {'OPENROUTER_API_KEY': 'sk-from-env'},
        ),
        isNull,
      );
    });

    test('an unset env name resolves to null, not to the name itself', () {
      expect(
        resolveProviderApiKey(
          const {'api_key_env': 'OPENROUTER_API_KEY'},
          env: const {},
        ),
        isNull,
      );
    });

    test('empty and whitespace-only values count as missing', () {
      for (final settings in const [
        {'api_key': ''},
        {'api_key': '   '},
        {'api_key_env': ''},
        {'api_key_env': '  '},
      ]) {
        expect(
          resolveProviderApiKey(
            settings,
            env: const {'EMPTY_NAME': ''},
          ),
          isNull,
          reason: '$settings must be keyless',
        );
      }
    });

    test('values are trimmed', () {
      expect(
        resolveProviderApiKey(
          const {'api_key': '  sk-padded  '},
          env: const {},
        ),
        'sk-padded',
      );
      expect(
        resolveProviderApiKey(
          const {'api_key_env': '  VARNAME  '},
          env: const {'VARNAME': ' sk-env  '},
        ),
        'sk-env',
      );
    });
  });

  group('isEnvReference', () {
    test(r'a ${NAME} ref is recognised', () {
      expect(isEnvReference(r'${OPENROUTER_API_KEY}'), isTrue);
    });

    test('a literal, a bare name, and near-misses are not', () {
      expect(isEnvReference('sk-literal'), isFalse);
      // The shipped `api_key_env` value: a bare name, never `${}`-wrapped.
      expect(isEnvReference('OPENROUTER_API_KEY'), isFalse);
      expect(isEnvReference(r'$OPENROUTER_API_KEY'), isFalse);
      expect(isEnvReference(r'${}'), isFalse);
      expect(isEnvReference(r'sk-${x}'), isFalse);
      expect(isEnvReference(r'prefix ${NAME}'), isFalse);
    });
  });

  group('envRefName', () {
    test('names the variable a ref points at', () {
      expect(envRefName(r'${OPENROUTER_API_KEY}'), 'OPENROUTER_API_KEY');
    });

    test('is null for a literal or a bare name', () {
      expect(envRefName('sk-literal'), isNull);
      expect(envRefName('OPENROUTER_API_KEY'), isNull);
      expect(envRefName(r'${}'), isNull);
    });
  });

  group('providerNeedsApiKey', () {
    test('is inferred from the block, not from a list of vendor names', () {
      expect(providerNeedsApiKey(const {'base_url': 'https://x'}), isFalse);
      expect(providerNeedsApiKey(const {'api_key': 'sk'}), isTrue);
      expect(providerNeedsApiKey(const {'apiKey': 'sk'}), isTrue);
      expect(providerNeedsApiKey(const {'api_key_env': 'MY_KEY'}), isTrue);
    });

    test('an empty declaration is not a credential', () {
      expect(providerNeedsApiKey(const {'api_key': ''}), isFalse);
      expect(providerNeedsApiKey(const {'api_key_env': ''}), isFalse);
    });

    test('a whitespace-only value still *declares* a credential', () {
      // Deliberate: the block asks for a key, so the GUI demands one (letting
      // the secure store fill it) instead of silently sending no header and
      // failing later at request time.
      expect(providerNeedsApiKey(const {'api_key': '   '}), isTrue);
      expect(
        resolveProviderApiKey(const {'api_key': '   '}, env: const {}),
        isNull,
        reason: 'but it is not usable',
      );
    });
  });
}
