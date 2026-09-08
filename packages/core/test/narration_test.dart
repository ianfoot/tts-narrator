import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  String writeInput({String? text}) =>
      (File('${dir.path}/story.txt')
            ..createSync(recursive: true)
            ..writeAsStringSync(text ?? _inputText))
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

  test('writes a combined track and records it in the manifest', () async {
    final input = writeInput();
    await narrate(config(input, format: 'mp3'));

    final combined = File('${dir.path}/out/story/story_full.mp3');
    expect(combined.existsSync(), isTrue);
    // Single segment: the combined track is a byte copy of the segment.
    expect(combined.readAsBytesSync(), provider.bytes);

    final segment = File('${dir.path}/out/story/story_1.mp3');
    expect(segment.existsSync(), isTrue);

    final manifest = jsonDecode(
      File('${dir.path}/out/story/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['combined_file'], 'story_full.mp3');
    expect(manifest['combined_bytes'], provider.bytes.length);
    expect(manifest['segments_deleted'], isFalse);
  });

  test('pools every WAV segment into one combined WAV', () async {
    final input = writeInput(text: '$_inputText\n\n$_inputText');
    final cfg = NarrationConfig(
      inputPath: input,
      profile: TtsModelProfile(
        alias: 'test',
        id: 'test/model',
        format: 'pcm',
        sampleRate: 24000,
        provider: provider.id,
      ),
      voice: 'VoiceOne',
      providerSettings: const {'api_key': 'sk-test'},
      outDir: '${dir.path}/out',
      minWords: 1,
    );
    await narrate(cfg);

    final pcm1 = _pcmPayload(
      File('${dir.path}/out/story/story_1.wav').readAsBytesSync(),
    );
    final pcm2 = _pcmPayload(
      File('${dir.path}/out/story/story_2.wav').readAsBytesSync(),
    );
    final combined = _pcmPayload(
      File('${dir.path}/out/story/story_full.wav').readAsBytesSync(),
    );
    expect(combined, [...pcm1, ...pcm2]);
  });

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

  group('sourceText (in-memory)', () {
    NarrationConfig typedConfig() => NarrationConfig(
      inputPath: 'story.txt',
      sourceText: _inputText,
      profile: TtsModelProfile(
        alias: 'test',
        id: 'test/model',
        format: 'mp3',
        provider: provider.id,
      ),
      voice: 'VoiceOne',
      providerSettings: const {'api_key': 'sk-test'},
      outDir: '${dir.path}/out',
    );

    test('plans from text without any backing file', () {
      // inputPath points nowhere; sourceText must satisfy the plan.
      final cfg = typedConfig();
      expect(planSegments(cfg), [_inputText]);
    });

    test('empty sourceText raises the inputPath-guarded planning error', () {
      final cfg = NarrationConfig(
        inputPath: 'story.txt',
        sourceText: '',
        profile: TtsModelProfile(
          alias: 'test',
          id: 'test/model',
          format: 'mp3',
          provider: provider.id,
        ),
        voice: 'VoiceOne',
        outDir: '${dir.path}/out',
      );
      expect(() => planSegments(cfg), throwsStateError);
    });

    test('sendWholeFile returns the entire source as one segment', () {
      const multi = 'Para alpha.\n\nPara beta.\n\nPara gamma.';
      final cfg = NarrationConfig(
        inputPath: 'story.txt',
        sourceText: multi,
        profile: TtsModelProfile(
          alias: 'test',
          id: 'test/model',
          format: 'mp3',
          provider: provider.id,
        ),
        voice: 'VoiceOne',
        outDir: '${dir.path}/out',
        // Segmentation settings are ignored in whole-file mode.
        minWords: 1,
        sendWholeFile: true,
      );
      expect(planSegments(cfg), [multi]);
    });

    test('sendWholeFile trims and normalizes line endings', () {
      final cfg = NarrationConfig(
        inputPath: 'story.txt',
        sourceText: 'One.\r\n\r\nTwo.',
        profile: TtsModelProfile(
          alias: 'test',
          id: 'test/model',
          format: 'mp3',
          provider: provider.id,
        ),
        voice: 'VoiceOne',
        outDir: '${dir.path}/out',
        sendWholeFile: true,
      );
      expect(planSegments(cfg), ['One.\n\nTwo.']);
    });

    test('sendWholeFile with only blank text raises the planning error', () {
      final cfg = NarrationConfig(
        inputPath: 'story.txt',
        sourceText: '   \n\n  ',
        profile: TtsModelProfile(
          alias: 'test',
          id: 'test/model',
          format: 'mp3',
          provider: provider.id,
        ),
        voice: 'VoiceOne',
        outDir: '${dir.path}/out',
        sendWholeFile: true,
      );
      expect(() => planSegments(cfg), throwsStateError);
    });

    test('sendWholeFile rejects a document over the whole-file cap', () {
      final tooLong = List.filled(maxWholeFileLength + 1, 'x').join();
      final cfg = NarrationConfig(
        inputPath: 'story.txt',
        sourceText: tooLong,
        profile: TtsModelProfile(
          alias: 'test',
          id: 'test/model',
          format: 'mp3',
          provider: provider.id,
        ),
        voice: 'VoiceOne',
        outDir: '${dir.path}/out',
        sendWholeFile: true,
      );
      expect(() => planSegments(cfg), throwsStateError);
    });

    test('sendWholeFile accepts a document at the cap', () {
      final atCap = List.filled(maxWholeFileLength, 'x').join();
      final cfg = NarrationConfig(
        inputPath: 'story.txt',
        sourceText: atCap,
        profile: TtsModelProfile(
          alias: 'test',
          id: 'test/model',
          format: 'mp3',
          provider: provider.id,
        ),
        voice: 'VoiceOne',
        outDir: '${dir.path}/out',
        sendWholeFile: true,
      );
      expect(planSegments(cfg), [atCap]);
    });

    test('the manifest records the whole-file cap in whole-file mode', () async {
      final cfg = NarrationConfig(
        inputPath: 'story.txt',
        sourceText: _inputText,
        profile: TtsModelProfile(
          alias: 'test',
          id: 'test/model',
          format: 'mp3',
          provider: provider.id,
        ),
        voice: 'VoiceOne',
        providerSettings: const {'api_key': 'sk-test'},
        outDir: '${dir.path}/out',
        sendWholeFile: true,
      );
      await narrate(cfg);

      final manifest = jsonDecode(
        File('${dir.path}/out/story/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(manifest['max_segment_length'], maxWholeFileLength);
    });

    test('sendWholeFile narrates the whole source in a single call', () async {
      final cfg = NarrationConfig(
        inputPath: 'story.txt',
        sourceText: '$_inputText\n\n$_inputText',
        profile: TtsModelProfile(
          alias: 'test',
          id: 'test/model',
          format: 'mp3',
          provider: provider.id,
        ),
        voice: 'VoiceOne',
        providerSettings: const {'api_key': 'sk-test'},
        outDir: '${dir.path}/out',
        sendWholeFile: true,
      );
      await narrate(cfg);

      expect(provider.callCount, 1);
      expect(provider.calls.single.input, '$_inputText\n\n$_inputText');

      // Output naming still derives from inputPath (the document name).
      final audio = File('${dir.path}/out/story/story_1.mp3');
      expect(audio.existsSync(), isTrue);
      expect(audio.readAsBytesSync(), provider.bytes);
    });

    test(
      'narrates from text via the provider without reading inputPath',
      () async {
        final cfg = typedConfig();
        await narrate(cfg);

        expect(provider.callCount, 1);
        expect(provider.calls.single.input, _inputText);

        // Output naming still derives from inputPath (the document name).
        final audio = File('${dir.path}/out/story/story_1.mp3');
        expect(audio.existsSync(), isTrue);
        expect(audio.readAsBytesSync(), provider.bytes);
      },
    );

    test('sampleLen limits an in-memory run', () async {
      const multi = '$_inputText\n\n$_inputText\n\n$_inputText\n\n$_inputText';
      final cfg = NarrationConfig(
        inputPath: 'story.txt',
        sourceText: multi,
        profile: TtsModelProfile(
          alias: 'test',
          id: 'test/model',
          format: 'mp3',
          provider: provider.id,
        ),
        voice: 'VoiceOne',
        providerSettings: const {'api_key': 'sk-test'},
        outDir: '${dir.path}/out',
        // minWords 1 keeps every paragraph its own segment = 4 segments.
        minWords: 1,
        sampleLen: 1,
      );
      expect(planSegments(cfg), hasLength(4));
      await narrate(cfg);
      expect(provider.callCount, 1);
    });
  });
}

String ascii(List<int> bytes) => String.fromCharCodes(bytes);

/// Extracts the `data` chunk payload from a WAV file's bytes.
List<int> _pcmPayload(Uint8List wav) {
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final id = String.fromCharCodes(wav.sublist(offset, offset + 4));
    final size = ByteData.sublistView(wav).getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      return wav.sublist(offset + 8, offset + 8 + size);
    }
    offset += 8 + size.toInt();
  }
  throw StateError('no data chunk');
}
