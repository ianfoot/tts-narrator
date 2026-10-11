import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'support/fake_provider.dart';
import 'support/wav_bytes.dart';

/// A voice-design model: no voice list, the narrator described in prose, and a
/// language the model accepts by name.
TtsModelProfile _profile({
  TtsWavResponseFormat wavResponseFormat = TtsWavResponseFormat.wav,
  bool sendsLanguage = true,
  bool supportsSpeed = true,
  bool instructAsInputPrefix = false,
}) =>
    TtsModelProfile(
      alias: 'design',
      id: 'test/design-model',
      provider: testProvider,
      formats: const [TtsAudioFormat.wav],
      wavResponseFormat: wavResponseFormat,
      sendsVoiceField: false,
      sendsInstructField: true,
      sendsLanguageField: sendsLanguage,
      supportsSpeed: supportsSpeed,
      instructAsInputPrefix: instructAsInputPrefix,
      defaultInstruct: 'A calm male narrator.',
    );

void main() {
  const settings = {'base_url': testBaseUrl, 'api_key': 'sk-test'};

  group('the design passage', () {
    // The transcript is not decoration: a cloning model adopting the clip is
    // handed `ref_text` and needs the words, so the passage is saved with every
    // voice rather than regenerated at use time.
    test('is non-empty and reads long enough to be worth cloning from', () {
      expect(kVoiceDesignPassage.trim(), isNotEmpty);
      final words = kVoiceDesignPassage.trim().split(RegExp(r'\s+'));
      expect(words.length, greaterThan(30));
    });

    // Two designs are only comparable if the difference between them is the
    // voice. A passage drawn from the user's document would make every
    // comparison meaningless.
    test('is fixed, so the same prose always yields the same reading', () {
      expect(kVoiceDesignPassage, same(kVoiceDesignPassage));
    });
  });

  group('a description that rides on the input', () {
    // mlx-audio's Fish Audio has no `instruct` field: given one it reads the
    // description aloud, so the clip opens with the instruction spoken instead
    // of the passage. It takes the description as a bracketed prefix on the
    // words themselves, which is the only shape it understands.
    test('prefixes the passage in brackets for a model that wants that', () {
      expect(
        inputForWire(
          _profile(instructAsInputPrefix: true),
          'The harbour lights.',
          'A smoker.',
        ),
        '[A smoker.] The harbour lights.',
      );
    });

    test('leaves the input alone for a model that reads a description', () {
      expect(
        inputForWire(_profile(), 'The harbour lights.', 'A smoker.'),
        'The harbour lights.',
      );
    });

    // No description means nothing to direct, and a leading `[]` would be a
    // malformed direction rather than an absent one.
    test('sends the passage bare when the description is blank', () {
      expect(
        inputForWire(
          _profile(instructAsInputPrefix: true),
          'The harbour lights.',
          '   ',
        ),
        'The harbour lights.',
      );
    });

    test('sends the passage bare when there is no description at all', () {
      expect(
        inputForWire(
          _profile(instructAsInputPrefix: true),
          'The harbour lights.',
          null,
        ),
        'The harbour lights.',
      );
    });
  });

  group('generating a voice sample', () {
    test('sends the standard passage as the input', () async {
      final provider = FakeTtsProvider();

      await generateVoiceSample(
        client: provider.client,
        profile: _profile(),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 1,
      );

      expect(provider.calls.single.input, kVoiceDesignPassage);
    });

    test('sends the voice description as instruct', () async {
      final provider = FakeTtsProvider();

      await generateVoiceSample(
        client: provider.client,
        profile: _profile(),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 1,
      );

      expect(provider.calls.single.instruct, 'A gravelly smoker.');
    });

    // A model that takes its description on the input must not also be sent an
    // `instruct`: it has no such field and reads whatever arrives there aloud,
    // so the clip would open with the description spoken and carry it twice.
    test('puts the description on the input and sends no instruct', () async {
      final provider = FakeTtsProvider();

      await generateVoiceSample(
        client: provider.client,
        profile: _profile(instructAsInputPrefix: true),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 1,
      );

      final call = provider.calls.single;
      expect(call.input, '[A gravelly smoker.] $kVoiceDesignPassage');
      expect(call.instruct, isNull);
    });

    // A design model writes the voice rather than selecting one. Sending an id
    // or a reference clip would ask it to imitate something while inventing it.
    test('sends no voice and no reference audio', () async {
      final provider = FakeTtsProvider();

      await generateVoiceSample(
        client: provider.client,
        profile: _profile(),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 1,
      );

      final call = provider.calls.single;
      expect(call.voice, isNull);
      expect(call.refAudio, isNull);
      expect(call.refText, isNull);
    });

    // The clip has to be something a cloning model can open later, so the
    // request is wav whatever mp3 the model could otherwise serve.
    test('always asks for wav, even for a model that also serves mp3', () async {
      final provider = FakeTtsProvider();

      await generateVoiceSample(
        client: provider.client,
        profile: _profile(),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 1,
      );

      expect(provider.calls.single.responseFormat, TtsAudioFormat.wav);
    });

    test('returns the provider bytes untouched for a natively-served wav',
        () async {
      final provider = FakeTtsProvider(bytes: wavFileBytes([1, 2, 3]));

      final sample = await generateVoiceSample(
        client: provider.client,
        profile: _profile(),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 1,
      );

      expect(sample.bytes, provider.bytes);
    });

    // The same pcm-to-wav rule narration obeys: a clip saved with a guessed
    // sample rate plays at the wrong pitch, which is worse than no clip.
    test('writes a wav header for a model serving raw samples', () async {
      final provider = FakeTtsProvider(
        bytes: [0, 1, 2, 3, 4, 5, 6, 7],
        sampleRate: 24000,
        channels: 1,
      );

      final sample = await generateVoiceSample(
        client: provider.client,
        profile: _profile(wavResponseFormat: TtsWavResponseFormat.pcm),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 1,
      );

      final written = wavFileBytes([0, 1, 2, 3, 4, 5, 6, 7]);
      expect(sample.bytes, written);
    });

    test('fails loudly when raw samples carry no sample rate', () async {
      final provider = FakeTtsProvider(
        bytes: [0, 1, 2, 3],
        sampleRate: null,
      );

      await expectLater(
        generateVoiceSample(
          client: provider.client,
          profile: _profile(wavResponseFormat: TtsWavResponseFormat.pcm),
          instruct: 'A gravelly smoker.',
          providerSettings: settings,
          attempts: 1,
        ),
        throwsStateError,
      );
    });

    test('reports how many generations produced this design', () async {
      final provider = FakeTtsProvider();

      final sample = await generateVoiceSample(
        client: provider.client,
        profile: _profile(),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 4,
      );

      expect(sample.attempts, 4);
    });

    // Both fields are honoured only when the model file says the backend reads
    // them; the same rule `narrate` applies, so a design cannot drift from the
    // narration path.
    test('passes language and speed only when the model accepts them', () async {
      final permissive = FakeTtsProvider();
      await generateVoiceSample(
        client: permissive.client,
        profile: _profile(),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 1,
        language: 'English',
        speed: 1.2,
      );
      expect(permissive.calls.single.language, 'English');
      expect(permissive.calls.single.speed, 1.2);

      final strict = FakeTtsProvider();
      await generateVoiceSample(
        client: strict.client,
        profile: _profile(sendsLanguage: false, supportsSpeed: false),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 1,
        language: 'English',
        speed: 1.2,
      );
      expect(strict.calls.single.language, isNull);
      expect(strict.calls.single.speed, isNull);
    });

    test('makes exactly one request per sample', () async {
      final provider = FakeTtsProvider();

      await generateVoiceSample(
        client: provider.client,
        profile: _profile(),
        instruct: 'A gravelly smoker.',
        providerSettings: settings,
        attempts: 1,
      );

      expect(provider.callCount, 1);
    });

    test('stops before the request when the run is cancelled', () async {
      final provider = FakeTtsProvider();
      final abort = AbortToken();

      await expectLater(
        generateVoiceSample(
          client: provider.client,
          profile: _profile(),
          instruct: 'A gravelly smoker.',
          providerSettings: settings,
          attempts: 1,
          abort: abort..cancel(),
        ),
        throwsA(isA<AbortException>()),
      );
      expect(provider.callCount, 0);
    });
  });
}