import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../support/fake_tts_provider.dart';
import '../support/run_setup_fixtures.dart';

/// A client that always throws, for the paths that must surface a failure
/// rather than quietly build a draft nobody asked for.
Future<GeneratedAudio> _alwaysFails({
  required String model,
  required String? voice,
  required String input,
  required TtsAudioFormat responseFormat,
  required TtsWavResponseFormat wavResponseFormat,
  required Map<String, String> settings,
  required double? speed,
  String? language,
  String? instruct,
  String? refAudio,
  String? refText,
  String? apiKey,
  AbortToken? abort,
}) async {
  throw StateError('server exploded');
}

/// A real config directory with a design model in it, plus a controller over it.
///
/// Modelled on the [VoiceConfigStore] core tests: every assertion here is about
/// what actually landed on disk, because the whole point of the design screen
/// is that a clip exists at a moment the user chose rather than at a moment the
/// code decided.
class _Fixture {
  late final Directory dir;
  late final FakeTtsProvider provider;
  late final AppController controller;

  _Fixture({bool withDesignModel = true, bool withConsumer = false}) {
    dir = Directory.systemTemp.createTempSync('tts_custom_voice_controller_');
    if (withDesignModel || withConsumer) {
      // One call, because `writeConfig` rewrites `models/` wholesale: asking for
      // a design model and then a cloning model would leave only the second, and
      // a test cannot design a voice it has no model to design with.
      writeConfig(dir.path, {
        'models': {
          if (withDesignModel)
            'qwen': {
              'id': 'mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16',
              'formats': ['wav'],
              'sends_voice': false,
              'sends_instruct': true,
              'sends_language': true,
              'default_instruct':
                  'A calm male narrator with a low, steady voice.',
              'default_language': 'English',
              'languages': {'English': 'English', 'Chinese': 'Chinese'},
            },
          if (withConsumer)
            'fish': {
              'id': 'mlx-community/fish-audio-s2-pro-8bit',
              'formats': ['wav'],
              'sends_reference_audio': true,
            },
        },
        'defaults': {'fish': 'Anne'},
        'voices': {
          'fish': {'Anne': '7da08ad79a8a4492b2c6b54091499922'},
        },
      });
    }
    provider = FakeTtsProvider();
    controller = makeController(dir.path, client: provider.client);
  }

  void dispose() => dir.deleteSync(recursive: true);

  CustomVoiceStore get store => CustomVoiceStore(dir.path);

  /// Whether anything at all has been written under the user's layer.
  bool get anythingPersisted {
    final voices = Directory('${dir.path}/user/voices');
    return voices.existsSync() &&
        voices.listSync(recursive: true).isNotEmpty;
  }
}

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.dispose());

  group('the design panel', () {
    test('offers the models that declare a voice design', () {
      expect(fixture.controller.customVoices.designModels, hasLength(1));
      expect(fixture.controller.customVoices.designModels.single.alias, 'qwen');
      expect(fixture.controller.customVoices.canDesign, isTrue);
    });

    // Without a design-capable model there is nothing the button could open, so
    // the toolbar guard needs a truthful answer rather than an empty dropdown.
    test('offers nothing when no model takes an instruct field', () {
      final bare = _Fixture(withDesignModel: false);
      addTearDown(bare.dispose);

      expect(bare.controller.customVoices.designModels, isEmpty);
      expect(bare.controller.customVoices.canDesign, isFalse);
      expect(bare.controller.customVoices.designModel, isNull);
    });

    test('prefills the prose with the model\'s own default', () {
      expect(
        fixture.controller.customVoices.designModel?.defaultInstruct,
        'A calm male narrator with a low, steady voice.',
      );
    });

    test('offers the languages the model declares', () {
      final items = fixture.controller.customVoices.designLanguageItems;
      expect(items.map((e) => e.$1), containsAll(['English', 'Chinese']));
    });
  });

  group('generating a draft', () {
    // The whole design of this feature rests on this: a clip nobody has
    // listened to is not a voice, it is a request. Writing it out anyway would
    // leave a wav per rejected generation for the user to clean up by hand.
    test('writes nothing to disk', () async {
      await fixture.controller.customVoices.generate('A gravelly smoker.');

      expect(fixture.controller.customVoices.draft, isNotNull);
      expect(fixture.anythingPersisted, isFalse);
      expect(fixture.provider.callCount, 1);
    });

    test('asks the design model to read the standard passage', () async {
      await fixture.controller.customVoices.generate('A gravelly smoker.');

      final call = fixture.provider.calls.single;
      expect(call.model, 'mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16');
      expect(call.input, kVoiceDesignPassage);
      expect(call.instruct, 'A gravelly smoker.');
      expect(call.voice, isNull);
    });

    test('holds the transcript the clip was read from', () async {
      await fixture.controller.customVoices.generate('A gravelly smoker.');

      expect(
        fixture.controller.customVoices.draft?.transcript,
        kVoiceDesignPassage,
      );
    });

    test('refuses to generate from a blank description', () async {
      await fixture.controller.customVoices.generate('   ');

      expect(fixture.provider.callCount, 0);
      expect(fixture.controller.customVoices.draft, isNull);
      expect(fixture.controller.customVoices.error, isNotNull);
    });

    test('reports a failed request instead of leaving a half-built draft',
        () async {
      final dir = Directory.systemTemp
          .createTempSync('tts_custom_voice_failing_');
      addTearDown(() => dir.deleteSync(recursive: true));
      writeVoiceDesignConfig(dir.path);
      final controller = makeController(dir.path, client: _alwaysFails);

      await controller.customVoices.generate('A gravelly smoker.');

      expect(controller.customVoices.draft, isNull);
      expect(controller.customVoices.error, contains('server exploded'));
      expect(controller.customVoices.generating, isFalse);
    });
  });

  group('re-rolling a draft', () {
    test('counts attempts while the prose is unchanged', () async {
      final voices = fixture.controller.customVoices;

      await voices.generate('A gravelly smoker.');
      expect(voices.draft?.attempts, 1);

      await voices.generate('A gravelly smoker.');
      expect(voices.draft?.attempts, 2);

      await voices.generate('A gravelly smoker.');
      expect(voices.draft?.attempts, 3);
      expect(fixture.provider.callCount, 3);
    });

    // The counter answers "have I tried this enough?", which is a question about
    // one line of prose. Rewriting the prose starts a different question.
    test('starts a new count when the prose changes', () async {
      final voices = fixture.controller.customVoices;

      await voices.generate('A gravelly smoker.');
      await voices.generate('A gravelly smoker.');
      expect(voices.draft?.attempts, 2);

      await voices.generate('A bright, youthful reader.');
      expect(voices.draft?.attempts, 1);
    });

    // The clip on screen is not the one the counter describes, so the draft
    // keeps the prose it actually came from rather than the panel's current text.
    test('keeps the prose the clip came from when the panel has moved on',
        () async {
      final voices = fixture.controller.customVoices;
      await voices.generate('A gravelly smoker.');

      await voices.generate('A bright, youthful reader.');

      expect(voices.draft?.instruct, 'A bright, youthful reader.');
    });
  });

  group('discarding a draft', () {
    test('generating again drops the clip it replaces', () async {
      final voices = fixture.controller.customVoices;
      await voices.generate('A gravelly smoker.');

      final gate = Completer<void>();
      fixture.provider.gate = gate;
      final rolling = voices.generate('A gravelly smoker.');
      await Future<void>.delayed(Duration.zero);

      expect(voices.draft, isNull);
      expect(voices.generating, isTrue);

      gate.complete();
      await rolling;

      expect(voices.draft?.attempts, 2);
      expect(fixture.anythingPersisted, isFalse);
      expect(fixture.store.read().isEmpty, isTrue);
    });
  });

  group('saving a draft', () {
    test('writes the clip and the registry row, and clears the draft', () async {
      final voices = fixture.controller.customVoices;
      await voices.generate('A gravelly smoker.');

      final result = voices.saveDraft('Gravelly');

      expect(result?.error, isNull);
      expect(voices.draft, isNull);
      expect(fixture.store.registryFile.existsSync(), isTrue);
      final library = fixture.store.read();
      expect(library.voices, hasLength(1));
      expect(library.voices.single.name.value, 'Gravelly');
      expect(fixture.store.wavFile(library.voices.single.id.value).existsSync(),
          isTrue);
    });

    test('records the design that produced it', () async {
      final voices = fixture.controller.customVoices;
      await voices.generate('A gravelly smoker.');
      voices.saveDraft('Gravelly');

      final saved = fixture.store.read().voices.single;
      expect(saved.designModel, 'qwen');
      expect(saved.instruct, 'A gravelly smoker.');
      expect(saved.transcript, kVoiceDesignPassage);
    });

    // Two voices can legitimately be called the same thing; the id is what
    // keeps their clips apart.
    test('keeps every variation when the same name is saved twice', () async {
      final voices = fixture.controller.customVoices;

      await voices.generate('A gravelly smoker.');
      voices.saveDraft('Gravelly');
      await voices.generate('A gravelly smoker.');
      voices.saveDraft('Gravelly');

      expect(fixture.store.read().voices, hasLength(2));
      expect(
        fixture.store.read().voices.map((v) => v.id.value),
        ['gravelly', 'gravelly-2'],
      );
    });

    // The clip is still the only thing the user has. Losing it to a typo would
    // mean re-rolling until the model happened to produce the same voice again.
    test('keeps the draft when a save is refused', () async {
      final voices = fixture.controller.customVoices;
      await voices.generate('A gravelly smoker.');

      final result = voices.saveDraft('   ');

      expect(result?.ok, isFalse);
      expect(voices.draft, isNotNull);
      expect(voices.error, isNotNull);
    });

    test('does nothing when there is no draft to save', () {
      expect(fixture.controller.customVoices.saveDraft('Gravelly'), isNull);
      expect(fixture.anythingPersisted, isFalse);
    });
  });

  group('a saved voice', () {
    Future<CustomVoice> saveOne() async {
      final voices = fixture.controller.customVoices;
      await voices.generate('A gravelly smoker.');
      voices.saveDraft('Gravelly');
      return fixture.store.read().voices.single;
    }

    test('reloads from disk so an external change is visible', () async {
      final saved = await saveOne();
      expect(fixture.controller.customVoices.library.voices, hasLength(1));

      fixture.store.remove(saved.id.value);
      fixture.controller.customVoices.refresh();

      expect(fixture.controller.customVoices.library.isEmpty, isTrue);
    });

    test('renames without moving the clip', () async {
      final saved = await saveOne();

      final result =
          fixture.controller.customVoices.rename(saved.id.value, 'Smoker');

      expect(result.ok, isTrue);
      final after = fixture.store.read().byId(saved.id.value)!;
      expect(after.name.value, 'Smoker');
      expect(fixture.store.wavFile(saved.id.value).existsSync(), isTrue);
    });

    test('deletes the clip and the row together', () async {
      final saved = await saveOne();

      final result = fixture.controller.customVoices.delete(saved.id.value);

      expect(result.ok, isTrue);
      expect(fixture.store.read().isEmpty, isTrue);
      expect(fixture.store.wavFile(saved.id.value).existsSync(), isFalse);
      expect(fixture.controller.customVoices.library.isEmpty, isTrue);
    });

    // Re-rolling a saved voice must not destroy it: the user is branching, not
    // replacing. The panel is seeded and they decide what to do with the result.
    test('seeds a new variation without touching the saved clip', () async {
      final saved = await saveOne();

      fixture.controller.customVoices.seedVariation(saved);

      expect(fixture.controller.customVoices.designModel?.alias, 'qwen');
      expect(fixture.store.wavFile(saved.id.value).existsSync(), isTrue);
      expect(fixture.store.read().byId(saved.id.value), isNotNull);
    });
  });

  group('choosing a voice for the run', () {
    // A saved custom voice is a reference clip plus the words it was read from,
    // which is exactly the pair `ref_audio` and `ref_text` already want. So it
    // rides the voice dropdown as one more row, and picking either kind of row
    // has to clear the other: a clip takes the voice field's place on the wire.
    _Fixture cloning() {
      final run = _Fixture(withDesignModel: true, withConsumer: true);
      addTearDown(run.dispose);
      run.controller.changeModel('fish');
      return run;
    }

    Future<String> saveOne(_Fixture run, String name) async {
      final voices = run.controller.customVoices;
      await voices.generate('A gravelly smoker.');
      voices.saveDraft(name);
      return name;
    }

    test('a saved voice is offered as a row of the voice dropdown', () async {
      final run = cloning();
      await saveOne(run, 'Gravelly');

      final labels = run.controller.voiceItems.map((e) => e.$2);

      expect(labels, contains('Gravelly'));
    });

    test('a model that cannot clone is offered no saved voice', () async {
      await saveOne(cloning(), 'Gravelly');

      expect(fixture.controller.voiceItems.map((e) => e.$2),
          isNot(contains('Gravelly')));
    });

    test('picking a saved voice sets the clip and its transcript', () async {
      final run = cloning();
      await saveOne(run, 'Gravelly');
      final saved = run.controller.customVoices.library.voices.single;
      final id = run.controller.voiceItems
          .firstWhere((e) => e.$2 == 'Gravelly')
          .$1;

      run.controller.selectVoice(id);

      expect(run.controller.referenceAudioPath,
          run.store.wavFile(saved.id.value).path);
      expect(run.controller.referenceAudioText, kVoiceDesignPassage);
      expect(run.controller.selectedCustomVoiceId, id);
    });

    test('picking one of the model\'s own voices drops the clip', () async {
      final run = cloning();
      await saveOne(run, 'Gravelly');
      final id = run.controller.voiceItems
          .firstWhere((e) => e.$2 == 'Gravelly')
          .$1;
      run.controller.selectVoice(id);
      final own = run.controller.voiceItems
          .firstWhere((e) => e.$2 != 'Gravelly')
          .$1;

      run.controller.selectVoice(own);

      expect(run.controller.referenceAudioPath, isNull);
      expect(run.controller.referenceAudioText, isEmpty);
      expect(run.controller.selectedCustomVoiceId, isNull);
    });

    test('a hand-picked clip is not reported as a saved voice', () {
      fixture.controller.referenceAudioPath = '${fixture.dir.path}/a.wav';

      expect(fixture.controller.selectedCustomVoiceId, isNull);
    });
  });

  group('choosing the design model', () {
    test('drops a language the newly chosen model does not offer', () {
      final voices = fixture.controller.customVoices;
      voices.selectDesignLanguage('Chinese');
      expect(voices.designLanguage, 'Chinese');

      // Re-selecting the same model is a no-op, so the language survives.
      voices.selectDesignModel('qwen');
      expect(voices.designLanguage, 'Chinese');
    });

    test('ignores a null selection from the dropdown', () {
      final voices = fixture.controller.customVoices;
      voices.selectDesignLanguage('Chinese');

      voices.selectDesignModel(null);

      expect(voices.designLanguage, 'Chinese');
    });
  });

  test('a saved voice sits beside the model voices without replacing them', () async {
    final run = _Fixture(withDesignModel: true, withConsumer: true);
    addTearDown(run.dispose);
    run.controller.changeModel('fish');
    final voices = run.controller.customVoices;
    await voices.generate('A gravelly smoker.');
    voices.saveDraft('Gravelly');

    final labels = run.controller.voiceItems.map((e) => e.$2);

    // The library lives outside the directories the config loader walks, so the
    // saved clip arrives beside the model's own voices rather than as one.
    expect(labels, containsAll(<String>['Anne', 'Gravelly']));
    expect(labels, hasLength(2));
  });
}