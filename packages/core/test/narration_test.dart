import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/narration/audio_format.dart';
import 'package:tts_narrator_core/src/narration/config.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';
import 'package:tts_narrator_core/src/narration/narration.dart';
import 'package:tts_narrator_core/src/narration/prompt.dart';
import 'package:tts_narrator_core/src/narration/wav.dart';

import 'support/fake_provider.dart';
import 'support/wav_bytes.dart';

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
    TtsAudioFormat outputFormat = TtsAudioFormat.mp3,
    bool promptStyle = false,
    bool sendsVoiceField = true,
    bool supportsSpeed = false,
    double speed = 1.0,
    bool sendsLanguageField = false,
    String? language,
    bool sendsInstructField = false,
    String? defaultInstruct,
    String? instruct,
    Map<String, String> providerSettings = const {'api_key': 'sk-test'},
  }) {
    return NarrationConfig(
      inputPath: inputPath,
      profile: TtsModelProfile(
        alias: 'test',
        id: 'test/model',
        formats: [outputFormat],
        promptStyle: promptStyle,
        sendsVoiceField: sendsVoiceField,
        supportsSpeed: supportsSpeed,
        sendsLanguageField: sendsLanguageField,
        sendsInstructField: sendsInstructField,
        defaultInstruct: defaultInstruct,
        provider: testProvider,
      ),
      outputFormat: outputFormat,
      voice: 'VoiceOne',
      voiceLabel: 'Voice One',
      language: language,
      instruct: instruct,
      speed: speed,
      // `narrate` validates the block before the first segment, so every test
      // needs a base URL; a test may still override or extend the map.
      providerSettings: {'base_url': testBaseUrl, ...providerSettings},
      outDir: '${dir.path}/out',
    );
  }

  /// A wav run for a model that declares `wav_response_format: pcm`.
  ///
  /// Separate from [config] because the declaration belongs in the profile, not
  /// in the run: it is what the model file says its backend can serve.
  NarrationConfig pcmSourcedConfig(String inputPath) => NarrationConfig(
    inputPath: inputPath,
    profile: TtsModelProfile(
      alias: 'test',
      id: 'test/model',
      formats: const [TtsAudioFormat.wav],
      wavResponseFormat: TtsWavResponseFormat.pcm,
      provider: testProvider,
    ),
    outputFormat: TtsAudioFormat.wav,
    voice: 'VoiceOne',
    providerSettings: const {'base_url': testBaseUrl, 'api_key': 'sk-test'},
    outDir: '${dir.path}/out',
  );

  test(
    'dispatches through the registered provider and writes mp3 bytes',
    () async {
      final input = writeInput();
      await narrate(config(input), client: provider.client);

      expect(provider.callCount, 1);
      final call = provider.calls.single;
      expect(call.model, 'test/model');
      expect(call.responseFormat, TtsAudioFormat.mp3);
      expect(call.voice, 'VoiceOne');
      expect(call.settings, {'base_url': testBaseUrl, 'api_key': 'sk-test'});
      expect(call.input, _inputText);

      final audioFile = File('${dir.path}/out/story/story_1.mp3');
      expect(audioFile.existsSync(), isTrue);
      expect(audioFile.readAsBytesSync(), provider.bytes);
    },
  );

  test('writes provider wav bytes to disk verbatim', () async {
    // The provider owns the container: a wav run never rewrites the payload,
    // so the file on disk is exactly what the client returned.
    final wav = FakeTtsProvider(bytes: wavFileBytes([1, 2, 3, 4]));
    final input = writeInput();
    await narrate(
      config(input, outputFormat: TtsAudioFormat.wav),
      client: wav.client,
    );

    final audioFile = File('${dir.path}/out/story/story_1.wav');
    expect(audioFile.existsSync(), isTrue);
    expect(audioFile.readAsBytesSync(), wav.bytes);
  });

  group('a wav run whose backend serves raw samples', () {
    // A model that declares `wav_response_format: pcm` is a promise that the
    // backend hands back bare samples and expects the app to write the header.
    // No OpenRouter model serves a WAV container -- its own validator rejects
    // `wav` -- so this is the path the three hosted models take, including
    // Gemini, whose only accepted wire format is pcm.
    test('writes a header at the rate the response reported', () async {
      final raw = FakeTtsProvider(
        bytes: [1, 2, 3, 4, 5, 6, 7, 8],
        sampleRate: 44100,
        channels: 1,
      );
      final input = writeInput();
      await narrate(pcmSourcedConfig(input), client: raw.client);

      final onDisk = File('${dir.path}/out/story/story_1.wav')
          .readAsBytesSync();
      final written = readWav(Uint8List.fromList(onDisk));
      // The samples are untouched and the rate is the one the backend said,
      // not one core invented: a wrong rate here plays at the wrong pitch.
      expect(written.data, [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(
        written.formatChunk,
        wavHeader(sampleRate: 44100, channels: 1, dataBytes: 8).sublist(12, 36),
        reason: 'the fmt chunk must carry the rate the response reported',
      );
      expect(onDisk.length, 44 + 8, reason: 'a canonical 44-byte header');
    });

    test('a native wav backend has its own header passed through', () async {
      // The mirror image: the model file leaves `wav_response_format` alone, so
      // the bytes already are a container and core must not prepend a second
      // header to them.
      final wav = FakeTtsProvider(
        bytes: wavFileBytes([9, 8, 7], sampleRate: 24000),
      );
      final input = writeInput();
      await narrate(
        config(input, outputFormat: TtsAudioFormat.wav),
        client: wav.client,
      );

      final onDisk = File('${dir.path}/out/story/story_1.wav')
          .readAsBytesSync();
      expect(onDisk, wavFileBytes([9, 8, 7], sampleRate: 24000));
      expect(onDisk.length, wavFileBytes([9, 8, 7]).length);
    });

    test('a response with no rate fails loudly rather than guessing', () async {
      // A header built from an invented rate is a file that plays, at the wrong
      // pitch, so a response that omits the rate is refused instead.
      final raw = FakeTtsProvider(bytes: [1, 2, 3, 4]);
      final input = writeInput();
      await expectLater(
        narrate(pcmSourcedConfig(input), client: raw.client),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('test/model'), contains('wav_response_format')),
          ),
        ),
      );
    });
  });

  test('writes a combined track and records it in the manifest', () async {
    final input = writeInput();
    await narrate(config(input), client: provider.client);

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
    // Every segment gets its own payload, so the combined track can only be
    // right if the payloads really were pooled.
    final wav = FakeTtsProvider(
      bytesFactory: (i) => sequencedWav(i),
    );
    final cfg = NarrationConfig(
      inputPath: input,
      profile: TtsModelProfile(
        alias: 'test',
        id: 'test/model',
        formats: const [TtsAudioFormat.wav],
        provider: provider.id,
      ),
      outputFormat: TtsAudioFormat.wav,
      voice: 'VoiceOne',
      providerSettings: const {'base_url': testBaseUrl, 'api_key': 'sk-test'},
      outDir: '${dir.path}/out',
      minWords: 1,
    );
    await narrate(cfg, client: wav.client);

    final first = readWav(
      File('${dir.path}/out/story/story_1.wav').readAsBytesSync(),
    ).data;
    final second = readWav(
      File('${dir.path}/out/story/story_2.wav').readAsBytesSync(),
    ).data;
    final combined = readWav(
      File('${dir.path}/out/story/story_full.wav').readAsBytesSync(),
    );
    expect(combined.data, [...first, ...second]);
    // The combined header is copied from the first segment, so the sample
    // rate survives without core having to invent or be told one.
    expect(
      combined.formatChunk,
      readWav(sequencedWav(0)).formatChunk,
    );
  });

  test('omits the voice field when sendsVoiceField is false', () async {
    final input = writeInput();
    await narrate(
      config(input, sendsVoiceField: false),
      client: provider.client,
    );
    expect(provider.calls.single.voice, isNull);
  });

  test('prompt-styled models pass buildPrompt output as the input', () async {
    final input = writeInput();
    final cfg = config(input, promptStyle: true);
    await narrate(cfg, client: provider.client);
    expect(provider.calls.single.input, buildPrompt(cfg, _inputText));
  });

  test('omits speed for a model that does not support it', () async {
    final input = writeInput();
    await narrate(
      config(input, supportsSpeed: false, speed: 1.4),
      client: provider.client,
    );
    expect(provider.calls.single.speed, isNull);
  });

  test('forwards speed for a model that supports it, even at 1.0', () async {
    final input = writeInput();
    await narrate(
      config(input, supportsSpeed: true, speed: 1.4),
      client: provider.client,
    );
    expect(provider.calls.single.speed, 1.4);
  });

  test('a capable model still gets its speed at the 1.0 default', () async {
    final input = writeInput();
    await narrate(config(input, supportsSpeed: true), client: provider.client);
    expect(provider.calls.single.speed, 1.0);
  });

  test('passes the language for a model that sends one', () async {
    final input = writeInput();
    await narrate(
      config(input, sendsLanguageField: true, language: 'j'),
      client: provider.client,
    );
    expect(provider.calls.single.language, 'j');
  });

  test('omits the language for a model that does not take one', () async {
    final input = writeInput();
    await narrate(config(input, language: 'j'), client: provider.client);
    expect(provider.calls.single.language, isNull);
  });

  test('records the language in the manifest only when it is sent', () async {
    final input = writeInput();

    await narrate(
      config(input, sendsLanguageField: true, language: 'b'),
      client: provider.client,
    );
    final sent = jsonDecode(
      File('${dir.path}/out/story/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(sent['language'], 'b');

    final plain = NarrationConfig(
      inputPath: input,
      profile: config(input).profile,
      outputFormat: TtsAudioFormat.mp3,
      voice: 'VoiceOne',
      language: 'b',
      providerSettings: const {'base_url': testBaseUrl, 'api_key': 'sk-test'},
      outDir: '${dir.path}/out2',
    );
    await narrate(plain, client: provider.client);
    final other = jsonDecode(
      File('${dir.path}/out2/story/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(other.containsKey('language'), isFalse);
  });

  group('voice design', () {
    test('sends the prose the user wrote', () async {
      final input = writeInput();
      await narrate(
        config(
          input,
          sendsVoiceField: false,
          sendsInstructField: true,
          instruct: 'A calm, low British male narrator.',
          defaultInstruct: 'The shipped default.',
        ),
        client: provider.client,
      );

      final call = provider.calls.single;
      expect(call.instruct, 'A calm, low British male narrator.');
      // Voice design replaces the voice id rather than adding to it.
      expect(call.voice, isNull);
    });

    test(
      "falls back to the model's own default when the user wrote nothing",
      () async {
        // Otherwise a model declaring the capability would be dispatched a request
        // describing no voice at all, which the vendor cannot fulfil.
        final input = writeInput();
        await narrate(
          config(
            input,
            sendsInstructField: true,
            defaultInstruct: 'The shipped default.',
          ),
          client: provider.client,
        );

        expect(provider.calls.single.instruct, 'The shipped default.');
      },
    );

    test('drops the prose for a model that does not take it', () async {
      // The gate is the capability, not the value: a stray `instruct` on a model
      // that has no such field must not reach the wire.
      final input = writeInput();
      await narrate(
        config(input, instruct: 'A calm, low British male narrator.'),
        client: provider.client,
      );

      expect(provider.calls.single.instruct, isNull);
    });
  });

  test('passes the resolved provider settings through untouched', () async {
    final input = writeInput();
    await narrate(
      config(input, providerSettings: {'api_key': 'sk-2', 'model_id': 'x'}),
      client: provider.client,
    );
    expect(provider.calls.single.settings, {
      'base_url': testBaseUrl,
      'api_key': 'sk-2',
      'model_id': 'x',
    });
  });

  group('provider block validation', () {
    // The shared factory always injects a base URL, so these build the config
    // directly in order to exercise a block that has none.
    NarrationConfig bareConfig(
      String inputPath, {
      required Map<String, String> providerSettings,
    }) => NarrationConfig(
      inputPath: inputPath,
      profile: const TtsModelProfile(
        alias: 'test',
        id: 'test/model',
        formats: [TtsAudioFormat.mp3],
        provider: testProvider,
      ),
      outputFormat: TtsAudioFormat.mp3,
      voice: 'VoiceOne',
      providerSettings: providerSettings,
      outDir: '${dir.path}/out',
    );

    test('names the block when base_url is missing', () async {
      final input = writeInput();
      await expectLater(
        narrate(
          bareConfig(input, providerSettings: const {}),
          client: provider.client,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('"$testProvider"'), contains('"base_url"')),
          ),
        ),
      );
      expect(provider.callCount, 0);
    });

    test('fails before creating the output directory', () async {
      final input = writeInput();
      await expectLater(
        narrate(
          bareConfig(input, providerSettings: const {}),
          client: provider.client,
        ),
        throwsA(isA<StateError>()),
      );
      expect(Directory('${dir.path}/out').existsSync(), isFalse);
    });

    test('accepts the endpoint alias for base_url', () async {
      final input = writeInput();
      await narrate(
        bareConfig(input, providerSettings: const {'endpoint': testBaseUrl}),
        client: provider.client,
      );
      expect(provider.callCount, 1);
    });

    test('treats a blank base_url as missing', () async {
      final input = writeInput();
      await expectLater(
        narrate(
          bareConfig(input, providerSettings: const {'base_url': '   '}),
          client: provider.client,
        ),
        throwsA(isA<StateError>()),
      );
      expect(provider.callCount, 0);
    });
  });

  group('sourceText (in-memory)', () {
    NarrationConfig typedConfig() => NarrationConfig(
      inputPath: 'story.txt',
      sourceText: _inputText,
      profile: TtsModelProfile(
        alias: 'test',
        id: 'test/model',
        formats: const [TtsAudioFormat.mp3],
        provider: provider.id,
      ),
      outputFormat: TtsAudioFormat.mp3,
      voice: 'VoiceOne',
      providerSettings: const {'base_url': testBaseUrl, 'api_key': 'sk-test'},
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
          formats: const [TtsAudioFormat.mp3],
          provider: provider.id,
        ),
        outputFormat: TtsAudioFormat.mp3,
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
          formats: const [TtsAudioFormat.mp3],
          provider: provider.id,
        ),
        outputFormat: TtsAudioFormat.mp3,
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
          formats: const [TtsAudioFormat.mp3],
          provider: provider.id,
        ),
        outputFormat: TtsAudioFormat.mp3,
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
          formats: const [TtsAudioFormat.mp3],
          provider: provider.id,
        ),
        outputFormat: TtsAudioFormat.mp3,
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
          formats: const [TtsAudioFormat.mp3],
          provider: provider.id,
        ),
        outputFormat: TtsAudioFormat.mp3,
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
          formats: const [TtsAudioFormat.mp3],
          provider: provider.id,
        ),
        outputFormat: TtsAudioFormat.mp3,
        voice: 'VoiceOne',
        outDir: '${dir.path}/out',
        sendWholeFile: true,
      );
      expect(planSegments(cfg), [atCap]);
    });

    test(
      'the manifest records the whole-file cap in whole-file mode',
      () async {
        final cfg = NarrationConfig(
          inputPath: 'story.txt',
          sourceText: _inputText,
          profile: TtsModelProfile(
            alias: 'test',
            id: 'test/model',
            formats: const [TtsAudioFormat.mp3],
            provider: provider.id,
          ),
          outputFormat: TtsAudioFormat.mp3,
          voice: 'VoiceOne',
          providerSettings: const {
            'base_url': testBaseUrl,
            'api_key': 'sk-test',
          },
          outDir: '${dir.path}/out',
          sendWholeFile: true,
        );
        await narrate(cfg, client: provider.client);

        final manifest = jsonDecode(
          File('${dir.path}/out/story/manifest.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(manifest['max_segment_length'], maxWholeFileLength);
      },
    );

    test('sendWholeFile narrates the whole source in a single call', () async {
      final cfg = NarrationConfig(
        inputPath: 'story.txt',
        sourceText: '$_inputText\n\n$_inputText',
        profile: TtsModelProfile(
          alias: 'test',
          id: 'test/model',
          formats: const [TtsAudioFormat.mp3],
          provider: provider.id,
        ),
        outputFormat: TtsAudioFormat.mp3,
        voice: 'VoiceOne',
        providerSettings: const {'base_url': testBaseUrl, 'api_key': 'sk-test'},
        outDir: '${dir.path}/out',
        sendWholeFile: true,
      );
      await narrate(cfg, client: provider.client);

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
        await narrate(cfg, client: provider.client);

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
          formats: const [TtsAudioFormat.mp3],
          provider: provider.id,
        ),
        outputFormat: TtsAudioFormat.mp3,
        voice: 'VoiceOne',
        providerSettings: const {'base_url': testBaseUrl, 'api_key': 'sk-test'},
        outDir: '${dir.path}/out',
        // minWords 1 keeps every paragraph its own segment = 4 segments.
        minWords: 1,
        sampleLen: 1,
      );
      expect(planSegments(cfg), hasLength(4));
      await narrate(cfg, client: provider.client);
      expect(provider.callCount, 1);
    });
  });
}

/// The payload for call [n] of the segment-pooling tests: a WAV holding a
/// single distinct sample value, so a pooled track can only come out right if
/// every segment's payload was actually consumed.
Uint8List sequencedWav(int n) => wavFileBytes([n + 1], sampleRate: 24000);
