import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/config.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';
import 'package:tts_narrator_core/src/narration/narration.dart';
import 'package:tts_narrator_core/src/narration/prompt.dart';
import 'package:tts_narrator_core/src/narration/tts_provider.dart';

import 'support/fake_provider.dart';

const _inputText =
    'The rain fell on the quiet street. '
    'It was an evening of small, patient sounds. '
    'Every window glowed behind drawn curtains.';

void main() {
  late Directory dir;
  late FakeTtsProvider provider;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_narrate_test_');
    provider = FakeTtsProvider();
    ttsProviderRegistry.register(provider.id, () => provider);
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  String writeInput() =>
      (File('${dir.path}/story.txt')
            ..createSync(recursive: true)
            ..writeAsStringSync(_inputText))
          .path;

  NarrationConfig config(
    String inputPath, {
    String? format,
    int? sampleRate,
    bool promptStyle = false,
    bool sendsVoiceField = true,
    Map<String, String> providerSettings = const {'api_key': 'sk-test'},
  }) {
    return NarrationConfig(
      inputPath: inputPath,
      profile: TtsModelProfile(
        alias: 'test',
        id: 'test/model',
        format: format ?? 'mp3',
        promptStyle: promptStyle,
        sendsVoiceField: sendsVoiceField,
        sampleRate: sampleRate,
        provider: provider.id,
      ),
      voice: 'VoiceOne',
      voiceLabel: 'Voice One',
      providerSettings: providerSettings,
      outDir: '${dir.path}/out',
    );
  }

  test(
    'dispatches through the registered provider and writes mp3 bytes',
    () async {
      final input = writeInput();
      await narrate(config(input));

      expect(provider.callCount, 1);
      final call = provider.calls.single;
      expect(call.model, 'test/model');
      expect(call.responseFormat, 'mp3');
      expect(call.voice, 'VoiceOne');
      expect(call.settings, {'api_key': 'sk-test'});
      expect(call.input, _inputText);

      final audioFile = File('${dir.path}/out/story/story_1.mp3');
      expect(audioFile.existsSync(), isTrue);
      expect(audioFile.readAsBytesSync(), provider.bytes);
    },
  );

  test(
    'wraps pcm output in a WAV header using the profile sample rate',
    () async {
      final input = writeInput();
      await narrate(config(input, format: 'pcm', sampleRate: 24000));

      final audioFile = File('${dir.path}/out/story/story_1.wav');
      expect(audioFile.existsSync(), isTrue);
      final bytes = audioFile.readAsBytesSync();
      expect(ascii(bytes.sublist(0, 4)), 'RIFF');
      expect(ascii(bytes.sublist(8, 12)), 'WAVE');
      expect(bytes, containsAllInOrder(provider.bytes));
    },
  );

  test('omits the voice field when sendsVoiceField is false', () async {
    final input = writeInput();
    await narrate(config(input, sendsVoiceField: false));
    expect(provider.calls.single.voice, isNull);
  });

  test('prompt-styled models pass buildPrompt output as the input', () async {
    final input = writeInput();
    final cfg = config(input, promptStyle: true);
    await narrate(cfg);
    expect(provider.calls.single.input, buildPrompt(cfg, _inputText));
  });

  test('passes the resolved provider settings through untouched', () async {
    final input = writeInput();
    await narrate(
      config(input, providerSettings: {'api_key': 'sk-2', 'model_id': 'x'}),
    );
    expect(provider.calls.single.settings, {
      'api_key': 'sk-2',
      'model_id': 'x',
    });
  });
}

String ascii(List<int> bytes) => String.fromCharCodes(bytes);
