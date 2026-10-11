import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

/// A real config directory on disk plus the store pointed at it, following the
/// same shape as the [VoiceConfigStore] tests: real files, so every assertion is
/// about what actually landed rather than about a mock.
class _Fixture {
  late final Directory dir;
  late final CustomVoiceStore store;

  _Fixture() {
    dir = Directory.systemTemp.createTempSync('tts_custom_voice_test_');
    store = CustomVoiceStore(dir.path);
  }

  void dispose() => dir.deleteSync(recursive: true);

  /// Saves a voice, failing the test if it was refused.
  CustomVoice save(String name, {List<int>? bytes}) {
    final result = store.add(
      name: name,
      bytes: Uint8List.fromList(bytes ?? [1, 2, 3]),
      modelAlias: 'qwen3_voicedesign',
      instruct: 'A calm male narrator.',
      transcript: kVoiceDesignPassage,
      language: 'English',
    );
    expect(result.error, isNull, reason: 'saving "$name" should not be refused');
    return result.voice!;
  }

  void writeRegistry(Object? body) {
    final file = store.registryFile;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(body));
  }
}

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.dispose());

  group('a library with nothing saved', () {
    // Before the first design the registry simply does not exist. That is the
    // state every user starts in and it must not read as an error.
    test('reads as empty rather than throwing', () {
      expect(fixture.store.registryFile.existsSync(), isFalse);
      expect(fixture.store.read().isEmpty, isTrue);
    });

    // A corrupt registry costs the user their saved voices, which is already
    // bad enough. It must not take narration down with it.
    test('reads as empty when the file is not valid json', () {
      fixture.writeRegistry('not json at all');
      expect(fixture.store.read().isEmpty, isTrue);
    });

    test('reads as empty when the file is not an object', () {
      fixture.writeRegistry(['a', 'list']);
      expect(fixture.store.read().isEmpty, isTrue);
    });

    test('reads as empty when `voices` is missing or the wrong type', () {
      fixture.writeRegistry({'schema': 1});
      expect(fixture.store.read().isEmpty, isTrue);
      fixture.writeRegistry({'voices': 'nope'});
      expect(fixture.store.read().isEmpty, isTrue);
    });
  });

  group('saving a voice', () {
    test('writes the clip and a registry row that reads back identically', () {
      final saved = fixture.save('Warm narrator');

      expect(fixture.store.wavFile(saved.id.value).existsSync(), isTrue);
      final library = fixture.store.read();
      expect(library.voices, hasLength(1));
      final read = library.byId(saved.id.value)!;
      expect(read.name.value, 'Warm narrator');
      expect(read.designModel, 'qwen3_voicedesign');
      expect(read.instruct, 'A calm male narrator.');
      expect(read.language, 'English');
      expect(read.transcript, kVoiceDesignPassage);
    });

    // The transcript is what a cloning model is handed alongside the clip; a
    // saved voice without it would be an unusable reference.
    test('keeps the transcript that travels with the clip', () {
      final saved = fixture.save('Warm narrator');
      expect(saved.transcript, kVoiceDesignPassage);
      expect(fixture.store.read().byId(saved.id.value)!.transcript,
          kVoiceDesignPassage);
    });

    test('refuses a blank name', () {
      final result = fixture.store.add(
        name: '   ',
        bytes: Uint8List.fromList([1]),
        modelAlias: 'design',
        instruct: 'A voice.',
        transcript: kVoiceDesignPassage,
      );

      expect(result.ok, isFalse);
      expect(result.error, isNotEmpty);
      expect(fixture.store.read().isEmpty, isTrue);
    });

    // Two designs can legitimately be called the same thing, so the clip
    // filenames are disambiguated rather than the save refused.
    test('numbers the clip filename rather than refusing a repeated name', () {
      final first = fixture.save('Warm narrator');
      final second = fixture.save('Warm narrator');
      final third = fixture.save('Warm narrator');

      expect(first.id.value, 'warm-narrator');
      expect(second.id.value, 'warm-narrator-2');
      expect(third.id.value, 'warm-narrator-3');
      expect(second.name.value, 'Warm narrator');
      expect(fixture.store.read().voices, hasLength(3));
    });

    test('slugs the filename so it is safe on any filesystem', () {
      expect(fixture.save('Warm / narrator: v2').id.value, 'warm-narrator-v2');
      expect(fixture.save('  ***  ').id.value, 'custom-voice');
      // A Windows device name cannot be a filename, so it falls back too.
      expect(fixture.store.add(
            name: 'CON',
            bytes: Uint8List.fromList([1]),
            modelAlias: 'design',
            instruct: 'A voice.',
            transcript: kVoiceDesignPassage,
          ).voice!.id.value,
          'custom-voice-2');
    });
  });

  group('renaming a voice', () {
    test('changes the label and leaves the clip where it was', () {
      final saved = fixture.save('Warm narrator');

      final result = fixture.store.rename(saved.id.value, 'Deeper voice');

      expect(result.ok, isTrue);
      final read = fixture.store.read().byId(saved.id.value)!;
      expect(read.name.value, 'Deeper voice');
      expect(read.id, saved.id);
      expect(fixture.store.wavFile(saved.id.value).existsSync(), isTrue);
    });

    // The point of keeping the id: a run already configured against this voice
    // keeps working across the rename.
    test('does not move the clip, so a configured run survives it', () {
      final saved = fixture.save('Warm narrator');
      fixture.store.rename(saved.id.value, 'Deeper voice');
      expect(fixture.store.wavFile(saved.id.value).existsSync(), isTrue);
    });

    test('refuses a blank name', () {
      final saved = fixture.save('Warm narrator');
      final result = fixture.store.rename(saved.id.value, '  ');
      expect(result.ok, isFalse);
      expect(fixture.store.read().byId(saved.id.value)!.name.value,
          'Warm narrator');
    });

    test('refuses a voice that is no longer there', () {
      expect(fixture.store.rename('nope', 'Anything').ok, isFalse);
    });
  });

  group('removing a voice', () {
    test('deletes the clip and the registry row', () {
      final saved = fixture.save('Warm narrator');

      final result = fixture.store.remove(saved.id.value);

      expect(result.ok, isTrue);
      expect(fixture.store.wavFile(saved.id.value).existsSync(), isFalse);
      expect(fixture.store.read().isEmpty, isTrue);
    });

    // The registry is the authority on what exists; a clip deleted behind the
    // app's back has already left the row as close to correct as it can get.
    test('still removes the row when the clip is already gone', () {
      final saved = fixture.save('Warm narrator');
      fixture.store.wavFile(saved.id.value).deleteSync();

      expect(fixture.store.remove(saved.id.value).ok, isTrue);
      expect(fixture.store.read().isEmpty, isTrue);
    });

    test('leaves other voices alone', () {
      final keep = fixture.save('Keep me');
      fixture.save('Drop me');

      final doomed = fixture.store
          .read()
          .voices
          .firstWhere((v) => v.name.value == 'Drop me');
      fixture.store.remove(doomed.id.value);

      final remaining = fixture.store.read().voices;
      expect(remaining, hasLength(1));
      expect(remaining.single.id, keep.id);
      expect(fixture.store.wavFile(keep.id.value).existsSync(), isTrue);
    });

    test('refuses a voice that is no longer there', () {
      expect(fixture.store.remove('nope').ok, isFalse);
    });
  });

  group('the registry file', () {
    // The registry belongs to the user as much as a model file does, so an
    // edit made in the app should never be the thing that drops a key.
    test('keeps keys this schema does not define', () {
      fixture.writeRegistry({
        'schema_version': 2,
        'user_note': 'keep me',
        'voices': <Object?>[],
      });
      fixture.save('Warm narrator');

      final raw =
          jsonDecode(fixture.store.registryFile.readAsStringSync()) as Map;
      expect(raw['schema_version'], 2);
      expect(raw['user_note'], 'keep me');
      expect((raw['voices'] as List), hasLength(1));
    });

    // `user/voices/` is not a directory the config loader walks, which is what
    // keeps a saved voice out of the `sends_voice: false` invariant.
    test('lives under the user overlay, out of reach of the loader', () {
      fixture.save('Warm narrator');
      expect(fixture.store.voicesDir, contains(kVoiceConfigOverlayDirName));
      expect(fixture.store.registryFile.existsSync(), isTrue);
    });

    // Without a usable transcript the entry cannot be handed to a cloning
    // model, so it is skipped rather than fatal to the whole library.
    test('skips an entry with no id or no transcript', () {
      fixture.writeRegistry({
        'voices': [
          {'id': 'no-transcript', 'name': 'Broken'},
          {'transcript': 'words', 'name': 'No id'},
          {'id': 'good', 'transcript': kVoiceDesignPassage, 'name': 'Good'},
        ],
      });

      final library = fixture.store.read();
      expect(library.voices, hasLength(1));
      expect(library.voices.single.id.value, 'good');
    });
  });
}