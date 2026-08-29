import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/abort.dart';
import 'package:tts_narrator_core/src/narration/tts_client.dart';

void main() {
  group('AbortToken', () {
    test('starts live and flips on cancel', () {
      final token = AbortToken();
      expect(token.cancelled, isFalse);
      token.cancel();
      expect(token.cancelled, isTrue);
      token.cancel();
      expect(token.cancelled, isTrue);
    });

    test('throwIfCancelled is a no-op until cancelled', () {
      final token = AbortToken();
      expect(token.throwIfCancelled, returnsNormally);
    });

    test('throwIfCancelled throws AbortException once cancelled', () {
      final token = AbortToken()..cancel();
      expect(token.throwIfCancelled, throwsA(isA<AbortException>()));
    });
  });

  group('AbortToken in TtsClient', () {
    test('an already-cancelled token aborts before any network call', () {
      final client = TtsClient(apiKey: 'sk-test');
      final token = AbortToken()..cancel();
      expect(
        () => client.synthesize(
          model: 'test/model',
          responseFormat: 'mp3',
          input: 'hello',
          abort: token,
        ),
        throwsA(isA<AbortException>()),
      );
    });
  });
}