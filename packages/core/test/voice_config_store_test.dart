import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

/// A real config directory on disk, plus the store pointed at it. Modelled as a
/// class rather than `late` locals so the helpers can be declared in any order
/// and still close over the directory.
class _Fixture {
  late final Directory dir;
  late final VoiceConfigStore store;

  _Fixture() {
    dir = Directory.systemTemp.createTempSync('tts_store_test_');
    store = VoiceConfigStore(dir.path);
    writeModel('fish', const {
      'id': 'fish-audio/s2.1',
      'default_voice': 'Alice',
      'voices': {
        'Alice': {'id': 'aaa', 'gender': 'female'},
        'Bob': {'id': 'bbb', 'gender': 'male'},
      },
    });
  }

  void dispose() => dir.deleteSync(recursive: true);

  File baseModel(String alias) => File('${dir.path}/models/$alias.json');

  File overlayModel(String alias) =>
      File('${dir.path}/user/models/$alias.json');

  /// Writes a model file into the downloaded layer, replacing any earlier one.
  ///
  /// Supplies a `formats` list when the body omits one. `formats` is required by
  /// the schema, and these fixtures are about voice editing rather than formats,
  /// so having each of them restate the same one-line declaration would be noise
  /// rather than documentation.
  void writeModel(String alias, Map<String, Object?> body) {
    final file = baseModel(alias);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'formats': const ['wav'],
        ...body,
      }),
    );
  }

  /// Writes the provider registry plus a `local` provider claiming [aliases],
  /// so [loadVoiceConfig] keeps the fixtures.
  void writeRegistry(List<String> aliases) {
    File('${dir.path}/$kVoiceConfigRegistryName').writeAsStringSync(
      jsonEncode({
        'providers': ['local'],
      }),
    );
    final provider = File('${dir.path}/$kVoiceConfigProvidersDir/local.json');
    provider.parent.createSync(recursive: true);
    provider.writeAsStringSync(
      jsonEncode({
        'models': aliases,
        'settings': {'base_url': 'http://localhost:8000/v1'},
      }),
    );
  }

  Map<String, dynamic> readOverlay(String alias) =>
      jsonDecode(overlayModel(alias).readAsStringSync())
          as Map<String, dynamic>;

  /// A Kokoro file carrying two voices that share the label `Santa`, so a write
  /// has to tell them apart by id.
  void writeKokoroWithSantas() => writeModel('kokoro', const {
    'id': 'hexgrad/kokoro-82m',
    'voices': {
      'bf_emma': {'name': 'Emma'},
      'bm_santa': {'name': 'Santa'},
      'am_santa': {'name': 'Santa'},
    },
  });

  Map<String, dynamic> readBase(String alias) =>
      jsonDecode(baseModel(alias).readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  late _Fixture f;

  setUp(() => f = _Fixture());
  tearDown(() => f.dispose());

  group('VoiceConfigStore reading', () {
    test('resolves rows from the downloaded file before any edit', () {
      expect(f.store.hasOverlayModel('fish'), isFalse);
      final rows = f.store.voicesFor('fish');
      // A row is keyed by the voice's id whatever the file was keyed by, so
      // these two come back under 'aaa'/'bbb' even though the file files them
      // under their names. That is what lets a write re-file them by id.
      expect(rows.map((r) => r.key), ['aaa', 'bbb']);
      expect(rows.map((r) => r.id), ['aaa', 'bbb']);
      expect(rows.map((r) => r.label), ['Alice', 'Bob']);
      expect(rows.first.gender, VoiceGender.female);
      expect(f.store.defaultVoiceKey('fish'), 'aaa');
    });

    test('a string shorthand entry resolves with key as both id and label', () {
      f.writeModel('gemini', const {
        'id': 'google/gemini',
        'voices': {'Charon': 'Charon'},
      });
      final row = f.store.voicesFor('gemini').single;
      expect(row.key, 'Charon');
      expect(row.id, 'Charon');
      expect(row.label, 'Charon');
    });

    test(
      'an id-keyed entry with a name keeps the id separate from the label',
      () {
        f.writeModel('kokoro', const {
          'id': 'hexgrad/kokoro-82m',
          'voices': {
            'bf_emma': {'name': 'Emma'},
          },
        });
        final row = f.store.voicesFor('kokoro').single;
        expect(row.key, 'bf_emma');
        expect(row.id, 'bf_emma');
        expect(row.label, 'Emma');
      },
    );

    test('default_voice matching by name resolves after normalisation', () {
      f.writeModel('kokoro', const {
        'id': 'hexgrad/kokoro-82m',
        'default_voice': 'Emma',
        'voices': {
          'bf_emma': {'name': 'Emma'},
        },
      });
      expect(f.store.defaultVoiceKey('kokoro'), 'bf_emma');
    });

    test('an unusable voice entry is skipped rather than surfaced', () {
      f.writeModel('gemini', const {
        'id': 'google/gemini',
        'voices': {
          'Good': 'Good',
          'Typo': {'idd': 'nope'},
        },
      });
      expect(f.store.voicesFor('gemini').map((r) => r.key), ['Good']);
    });

    test('an unknown alias yields no rows and no default', () {
      expect(f.store.voicesFor('missing'), isEmpty);
      expect(f.store.defaultVoiceKey('missing'), isNull);
      expect(f.store.readModelJson('missing'), isNull);
    });

    test('a malformed model file surfaces as a configuration error', () {
      f.baseModel('gemini').writeAsStringSync('{not json');
      expect(
        () => f.store.voicesFor('gemini'),
        throwsA(isA<VoiceConfigurationError>()),
      );
    });
  });

  group('writeModelJson', () {
    test('writes into the overlay and leaves the downloaded file alone', () {
      final json = f.store.readModelJson('fish')!;
      json['display_name'] = 'Edited';
      f.store.writeModelJson('fish', json);

      expect(f.store.hasOverlayModel('fish'), isTrue);
      expect(f.readOverlay('fish')['display_name'], 'Edited');
      expect(f.readBase('fish').containsKey('display_name'), isFalse);
    });

    test('leaves no temp file behind', () {
      final json = f.store.readModelJson('fish')!;
      f.store.writeModelJson('fish', json);
      final temps = f.dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.tmp'));
      expect(temps, isEmpty);
    });

    test('is pretty-printed and carries no trailing newline', () {
      final json = f.store.readModelJson('fish')!;
      f.store.writeModelJson('fish', json);
      final text = f.overlayModel('fish').readAsStringSync();
      expect(text, contains('\n  '));
      expect(text.endsWith('\n'), isFalse);
    });

    test('preserves keys the schema does not know about', () {
      final json = f.store.readModelJson('fish')!;
      json['some_future_key'] = {'nested': true};
      f.store.writeModelJson('fish', json);
      expect(f.readOverlay('fish')['some_future_key'], {'nested': true});
    });
  });

  group('saveVoice', () {
    test('adds a row keyed by its id, with the label in a name', () {
      final edit = f.store.saveVoice(
        'fish',
        label: 'Custom',
        id: 'ccc',
        gender: VoiceGender.neutral,
      );
      expect(edit.ok, isTrue);
      final voices = f.readOverlay('fish')['voices'] as Map<String, dynamic>;
      expect(voices['ccc'], {'name': 'Custom', 'gender': 'neutral'});
    });

    test('replaces a row in place, keeping file order', () {
      f.store.saveVoice('fish', key: 'aaa', label: 'Alicia', id: 'aaa');
      final voices = f.readOverlay('fish')['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['aaa', 'bbb']);
      expect(voices['aaa'], {'name': 'Alicia', 'gender': 'female'});
    });

    test('carries the default across a rename', () {
      f.store.saveVoice('fish', key: 'aaa', label: 'Alicia', id: 'aaa');
      expect(f.readOverlay('fish')['default_voice'], 'aaa');
      expect(f.store.defaultVoiceKey('fish'), 'aaa');
    });

    test('rejects a blank label', () {
      final edit = f.store.saveVoice('fish', label: '  ', id: 'ccc');
      expect(edit.ok, isFalse);
      expect(edit.error, isNotNull);
      expect(f.store.hasOverlayModel('fish'), isFalse);
    });

    test('rejects a blank id', () {
      final edit = f.store.saveVoice('fish', label: 'Custom', id: '  ');
      expect(edit.ok, isFalse);
      expect(f.store.hasOverlayModel('fish'), isFalse);
    });

    test('accepts a duplicate label, which the id keys apart', () {
      // Kokoro ships three voices named "Santa", so refusing on a repeated label
      // would make every edit to that model unwritable. The id is the key, so
      // two Santas are two entries rather than one that overwrites the other.
      final edit = f.store.saveVoice('fish', label: 'Bob', id: 'ccc');
      expect(edit.ok, isTrue);
      final voices = f.readOverlay('fish')['voices'] as Map<String, dynamic>;
      expect(voices['bbb'], {'name': 'Bob', 'gender': 'male'});
      expect(voices['ccc'], {'name': 'Bob'});
    });

    test('rejects a duplicate id, which would vanish from the picker', () {
      expect(f.store.saveVoice('fish', label: 'Clone', id: 'bbb').ok, isFalse);
    });

    test('rejects an edit to a key that is gone', () {
      final edit = f.store.saveVoice(
        'fish',
        key: 'Nobody',
        label: 'Ghost',
        id: 'ccc',
      );
      expect(edit.ok, isFalse);
    });

    test('rejects a write to a model with no file', () {
      expect(f.store.saveVoice('missing', label: 'X', id: 'y').ok, isFalse);
    });
  });

  group('removeVoice', () {
    test('removes a non-default row', () {
      expect(f.store.removeVoice('fish', 'bbb').ok, isTrue);
      final voices = f.readOverlay('fish')['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['aaa']);
    });

    test('removes one of several voices sharing a label', () {
      f.writeKokoroWithSantas();
      final edit = f.store.removeVoice('kokoro', 'am_santa');
      expect(edit.ok, isTrue);
      // The write keys by id, so dropping one Santa cannot collapse the other
      // into it -- which is what the old label-keyed write had to refuse.
      final voices = f.readOverlay('kokoro')['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['bf_emma', 'bm_santa']);
      expect(voices['bm_santa'], {'name': 'Santa'});
    });

    test('refuses to remove the default voice', () {
      final edit = f.store.removeVoice('fish', 'aaa');
      expect(edit.ok, isFalse);
      expect(edit.error, contains('default'));
      expect(f.store.hasOverlayModel('fish'), isFalse);
    });
  });

  group('setDefaultVoice', () {
    test('points default_voice at the chosen row', () {
      expect(f.store.setDefaultVoice('fish', 'bbb').ok, isTrue);
      expect(f.readOverlay('fish')['default_voice'], 'bbb');
      expect(f.store.defaultVoiceKey('fish'), 'bbb');
    });

    test('rejects an unknown key', () {
      expect(f.store.setDefaultVoice('fish', 'Nobody').ok, isFalse);
    });

    test('points the default at one of several voices sharing a label', () {
      // The write keys by id, so naming one of the Santas cannot disturb the
      // others -- the case the old label-keyed write had to refuse outright.
      f.writeKokoroWithSantas();
      expect(f.store.setDefaultVoice('kokoro', 'bm_santa').ok, isTrue);
      expect(f.readOverlay('kokoro')['default_voice'], 'bm_santa');
      final voices = f.readOverlay('kokoro')['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['bf_emma', 'bm_santa', 'am_santa']);
    });
  });

  group('default_voice is carried, never dropped', () {
    // `default_voice` is a key into the same map a write rewrites, and
    // VoiceConfig.resolveVoice also accepts a bare id. An edit to an unrelated
    // voice must therefore never remove a value it could not resolve: losing it
    // un-defaults the model, after which defaultVoiceFor throws and the model
    // cannot be selected at all.

    test('survives a removal of an unrelated voice', () {
      expect(f.store.removeVoice('fish', 'bbb').ok, isTrue);
      expect(f.readOverlay('fish')['default_voice'], 'aaa');
    });

    test('survives an edit to an unrelated voice', () {
      expect(
        f.store.saveVoice('fish', key: 'bbb', label: 'Robert', id: 'bbb').ok,
        isTrue,
      );
      expect(f.readOverlay('fish')['default_voice'], 'aaa');
    });

    test('a default named by id is carried even when it is not a file key', () {
      f.writeModel('kokoro', const {
        'id': 'hexgrad/kokoro-82m',
        'default_voice': 'bf_emma',
        'voices': {
          'bf_emma': {'name': 'Emma'},
          'bm_george': {'name': 'George'},
        },
      });
      expect(f.store.defaultVoiceKey('kokoro'), 'bf_emma');
      expect(f.store.removeVoice('kokoro', 'bm_george').ok, isTrue);
      // Left as the id the write keys the block by, which still resolves.
      expect(f.readOverlay('kokoro')['default_voice'], 'bf_emma');
    });

    test('a default naming nothing in the list is left exactly as found', () {
      // resolveVoice falls back to the raw string when the id is absent from
      // `voices`, so this value still works and the Fish README documents it.
      f.writeModel('fish', const {
        'id': 'fish-audio/s2.1',
        'default_voice': '89f41ea230034706881f85a8227d6ab9',
        'voices': {
          'Alice': {'id': 'aaa'},
          'Bob': {'id': 'bbb'},
        },
      });
      expect(f.store.defaultVoiceKey('fish'), isNull);
      expect(f.store.removeVoice('fish', 'bbb').ok, isTrue);
      expect(
        f.readOverlay('fish')['default_voice'],
        '89f41ea230034706881f85a8227d6ab9',
      );
    });

    test('a default naming a skipped entry is still carried', () {
      // An unusable entry never becomes a row, so the default cannot resolve
      // against it -- but the loader may still honour the raw string, and a
      // write has no standing to delete it either way.
      f.writeModel('fish', const {
        'id': 'fish-audio/s2.1',
        'default_voice': 'Ghost',
        'voices': {
          'Alice': {'id': 'aaa'},
          'Broken': {'id': ''},
        },
      });
      expect(f.store.removeVoice('fish', 'aaa').ok, isTrue);
      expect(f.readOverlay('fish')['default_voice'], 'Ghost');
    });

    test('a blank default is carried too, rather than tidied away', () {
      // Nothing here claims to understand the value, so the store leaves it
      // alone -- the same rule it follows for keys it does not own.
      f.writeModel('fish', const {
        'id': 'fish-audio/s2.1',
        'default_voice': '',
        'voices': {
          'Alice': {'id': 'aaa'},
          'Bob': {'id': 'bbb'},
        },
      });
      expect(f.store.removeVoice('fish', 'bbb').ok, isTrue);
      expect(f.readOverlay('fish')['default_voice'], '');
    });
  });

  group('revertModel', () {
    test('drops the overlay so the downloaded file shows through again', () {
      final json = f.store.readModelJson('fish')!;
      json['display_name'] = 'Edited';
      f.store.writeModelJson('fish', json);
      expect(f.store.readModelJson('fish')!['display_name'], 'Edited');

      expect(f.store.revertModel('fish'), isTrue);
      expect(f.store.hasOverlayModel('fish'), isFalse);
      expect(
        f.store.readModelJson('fish')!.containsKey('display_name'),
        isFalse,
      );
    });

    test('reports false when there was no override', () {
      expect(f.store.revertModel('fish'), isFalse);
    });
  });

  group('normalisation on write', () {
    test('leaves an id-keyed entry keyed by its id', () {
      f.writeModel('kokoro', const {
        'id': 'hexgrad/kokoro-82m',
        'default_voice': 'Emma',
        'voices': {
          'bf_emma': {'name': 'Emma'},
        },
      });
      f.store.saveVoice('kokoro', key: 'bf_emma', label: 'Emma', id: 'bf_emma');
      final json = f.readOverlay('kokoro');
      final voices = json['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['bf_emma']);
      // The `name` survives as metadata; the id is the key, so it is not
      // repeated in the value.
      expect(voices['bf_emma'], {'name': 'Emma'});
      expect(json['default_voice'], 'bf_emma');
    });

    test('re-files a name-keyed entry under its id, keeping the name', () {
      // The migration case: a file written before this shape was normalised now
      // lands on the id key, with the display name carried across rather than
      // promoted to the key where it could collide.
      f.writeModel('fish', const {
        'id': 'fish-audio/s2.1',
        'default_voice': 'Alice',
        'voices': {
          'Alice': {'id': 'aaa', 'gender': 'female', 'language': 'en-gb'},
          'Bob': {'id': 'bbb', 'gender': 'male', 'language': 'en-us'},
        },
      });
      f.store.saveVoice('fish', key: 'aaa', label: 'Alice', id: 'aaa');
      final json = f.readOverlay('fish');
      final voices = json['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['aaa', 'bbb']);
      expect(voices['aaa'], {
        'name': 'Alice',
        'gender': 'female',
        'language': 'en-gb',
      });
      expect(voices['bbb'], {
        'name': 'Bob',
        'gender': 'male',
        'language': 'en-us',
      });
      expect(json['default_voice'], 'aaa');
    });

    test('drops a name that would only repeat the id', () {
      // A string shorthand reads as id == label == key, so writing it back
      // spells the id twice over. The reader falls back to the id for the label,
      // so nothing is lost.
      f.writeModel('gemini', const {
        'id': 'google/gemini',
        'voices': {'Charon': 'Charon'},
      });
      f.store.saveVoice('gemini', key: 'Charon', label: 'Charon', id: 'Charon');
      final voices = f.readOverlay('gemini')['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['Charon']);
      expect(voices['Charon'], isEmpty);
    });

    test('reads a model whose voices arrived as a bare id list', () {
      // The list form is how gemini.json ships, and reading it as no rows at
      // all would leave an editable model with an empty picker rather than the
      // voices its file already declares.
      f.writeModel('gemini', const {
        'id': 'google/gemini',
        'voices': ['Charon', 'Zephyr'],
      });
      final rows = f.store.voicesFor('gemini');
      expect(rows.map((r) => r.key), ['Charon', 'Zephyr']);
      expect(rows.map((r) => r.id), ['Charon', 'Zephyr']);
      expect(rows.map((r) => r.label), ['Charon', 'Zephyr']);
    });

    test('keeps a language-prefixed id intact so the model still reads it', () {
      f.writeModel('kokoro', const {
        'id': 'hexgrad/kokoro-82m',
        'voices': {
          'bf_emma': {'name': 'Emma'},
        },
      });
      f.store.saveVoice(
        'kokoro',
        key: 'bf_emma',
        label: 'Emma',
        id: 'bf_emma',
        gender: VoiceGender.female,
      );
      final voices = f.readOverlay('kokoro')['voices'] as Map<String, dynamic>;
      expect(voices['bf_emma'], {'name': 'Emma', 'gender': 'female'});
    });

    test('leaves the non-voice half of the model file untouched', () {
      f.writeModel('kokoro', const {
        'id': 'hexgrad/kokoro-82m',
        'display_name': 'Kokoro 82M',
        'format': 'mp3',
        'speed': true,
        'sends_language': true,
        'languages': {'b': 'British English'},
        'pricing': {'usd_per_m_chars': 0.62},
        'voices': {
          'bf_emma': {'name': 'Emma'},
        },
      });
      f.store.saveVoice('kokoro', key: 'bf_emma', label: 'Emma', id: 'bf_emma');
      final json = f.readOverlay('kokoro');
      expect(json['id'], 'hexgrad/kokoro-82m');
      expect(json['display_name'], 'Kokoro 82M');
      expect(json['format'], 'mp3');
      expect(json['speed'], isTrue);
      expect(json['sends_language'], isTrue);
      expect(json['languages'], {'b': 'British English'});
      expect(json['pricing'], {'usd_per_m_chars': 0.62});
    });
  });

  group('loader agreement', () {
    test('a saved edit is what the next load reads', () {
      f.store.saveVoice(
        'fish',
        label: 'Custom',
        id: 'ccc',
        gender: VoiceGender.male,
      );
      f.writeRegistry(const ['fish']);
      final (cfg, warnings) = loadVoiceConfig(f.dir.path);
      expect(warnings, isEmpty);
      final voice = cfg.voices['fish']!['ccc']!;
      expect(voice.id, 'ccc');
      expect(voice.name, 'Custom');
      expect(voice.gender, VoiceGender.male);
      expect(cfg.models['fish']!.provider, 'local');
    });

    test('the overlay is picked up without touching the base file', () {
      final base = f.store.readDownloadedModelJson('fish')!;
      base['display_name'] = 'Edited';
      f.store.writeModelJson('fish', base);
      expect(
        f.store.readDownloadedModelJson('fish')!.containsKey('display_name'),
        isFalse,
      );
      expect(f.store.readModelJson('fish')!['display_name'], 'Edited');
    });
  });
}
