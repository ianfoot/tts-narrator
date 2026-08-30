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
