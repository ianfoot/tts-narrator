import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/abort.dart';
import 'package:tts_narrator_core/src/narration/config.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';
import 'package:tts_narrator_core/src/narration/narration.dart';
import 'package:tts_narrator_core/src/narration/tts_provider.dart';

import 'support/fake_provider.dart';

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

    test('onCancel fires each registered callback once on cancel', () {
      final token = AbortToken();
      var first = 0;
      var second = 0;
      token.onCancel(() => first++);
      token.onCancel(() => second++);
      token.cancel();
      expect(first, 1);
      expect(second, 1);
      token.cancel();
      expect(first, 1);
      expect(second, 1);
    });

    test('onCancel registered after cancel fires immediately', () {
      final token = AbortToken()..cancel();
      var fired = 0;
      final unsubscribe = token.onCancel(() => fired++);
      expect(fired, 1);
      unsubscribe();
      token.cancel();
      expect(fired, 1);
    });

    test('unsubscribing prevents a later cancel from firing the callback', () {
      final token = AbortToken();
      var fired = 0;
      final unsubscribe = token.onCancel(() => fired++);
      unsubscribe();
      token.cancel();
      expect(fired, 0);
    });

    test('a throwing subscriber does not block the rest from firing', () {
      final token = AbortToken();
      var fired = 0;
      token.onCancel(() => throw StateError('hook failed'));
      token.onCancel(() => fired++);
      token.cancel();
      expect(fired, 1);
    });
  });

  group('AbortToken in narrate', () {
    late Directory dir;
    late FakeTtsProvider provider;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tts_abort_test_');
      provider = FakeTtsProvider();
      ttsProviderRegistry.register(provider.id, () => provider);
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test(
      'a pre-cancelled token aborts before the provider is called',
      () async {
        final input = File('${dir.path}/story.txt')
          ..writeAsStringSync(
            'Hello world. Another sentence here.'
            'And a third one to be safe.',
          );
        final config = NarrationConfig(
          inputPath: input.path,
          profile: const TtsModelProfile(
            alias: 'test',
            id: 'test/model',
            provider: 'fake',
          ),
          voice: 'v',
        );

        await expectLater(
          narrate(config, abort: AbortToken()..cancel()),
          throwsA(isA<AbortException>()),
        );
        expect(provider.callCount, 0);
      },
    );
  });
}
