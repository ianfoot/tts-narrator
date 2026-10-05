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
        'Alice': {
          'id': 'aaa',
          'gender': 'female',
        },
        'Bob': {'id': 'bbb', 'gender': 'male'},
      },
    });
  }

  void dispose() => dir.deleteSync(recursive: true);

  File baseModel(String alias) => File('${dir.path}/models/$alias.json');

  File overlayModel(String alias) => File('${dir.path}/user/models/$alias.json');

  /// Writes a model file into the downloaded layer, replacing any earlier one.
  void writeModel(String alias, Map<String, Object?> body) {
    final file = baseModel(alias);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(body));
  }

  /// Writes the provider registry plus a `local` provider claiming [aliases],
  /// so [loadVoiceConfig] keeps the fixtures.
  void writeRegistry(List<String> aliases) {
    File('${dir.path}/$kVoiceConfigRegistryName').writeAsStringSync(
      jsonEncode({'providers': ['local']}),
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
      expect(rows.map((r) => r.key), ['Alice', 'Bob']);
      expect(rows.map((r) => r.id), ['aaa', 'bbb']);
      expect(rows.first.label, 'Alice');
      expect(rows.first.gender, VoiceGender.female);
      expect(f.store.defaultVoiceKey('fish'), 'Alice');
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

    test('an id-keyed entry with a name keeps the id separate from the label', () {
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
    });

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
    test('adds a row in the canonical shape', () {
      final edit = f.store.saveVoice(
        'fish',
        label: 'Custom',
        id: 'ccc',
        gender: VoiceGender.neutral,
      );
      expect(edit.ok, isTrue);
      final voices = f.readOverlay('fish')['voices'] as Map<String, dynamic>;
      expect(voices['Custom'], {'id': 'ccc', 'gender': 'neutral'});
    });

    test('replaces a row in place, keeping file order', () {
      f.store.saveVoice('fish', key: 'Alice', label: 'Alicia', id: 'aaa');
      final voices = f.readOverlay('fish')['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['Alicia', 'Bob']);
    });

    test('carries the default across a rename', () {
      f.store.saveVoice('fish', key: 'Alice', label: 'Alicia', id: 'aaa');
      expect(f.readOverlay('fish')['default_voice'], 'Alicia');
      expect(f.store.defaultVoiceKey('fish'), 'Alicia');
    });

    test('leaves a non-default voice alone when another is renamed', () {
      f.store.saveVoice('fish', key: 'Bob', label: 'Robert', id: 'bbb');
      expect(f.readOverlay('fish')['default_voice'], 'Alice');
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

    test('rejects a duplicate label', () {
      expect(f.store.saveVoice('fish', label: 'Bob', id: 'ccc').ok, isFalse);
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
      expect(f.store.removeVoice('fish', 'Bob').ok, isTrue);
      final voices = f.readOverlay('fish')['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['Alice']);
    });

    test('refuses a removal that would collapse a duplicate label', () {
      f.writeModel('kokoro', const {
        'id': 'hexgrad/kokoro-82m',
        'voices': {
          'Emma': {'id': 'bf_emma'},
          'bm_santa': {'name': 'Santa', 'id': 'bm_santa'},
          'am_santa': {'name': 'Santa', 'id': 'am_santa'},
        },
      });
      final edit = f.store.removeVoice('kokoro', 'Emma');
      expect(edit.ok, isFalse);
      expect(edit.error, contains('Santa'));
      expect(f.store.hasOverlayModel('kokoro'), isFalse);
    });

    test('refuses to remove the default voice', () {
      final edit = f.store.removeVoice('fish', 'Alice');
      expect(edit.ok, isFalse);
      expect(edit.error, contains('default'));
      expect(f.store.hasOverlayModel('fish'), isFalse);
    });
  });

  group('setDefaultVoice', () {
    test('points default_voice at the chosen row', () {
      expect(f.store.setDefaultVoice('fish', 'Bob').ok, isTrue);
      expect(f.readOverlay('fish')['default_voice'], 'Bob');
      expect(f.store.defaultVoiceKey('fish'), 'Bob');
    });

    test('rejects an unknown key', () {
      expect(f.store.setDefaultVoice('fish', 'Nobody').ok, isFalse);
    });

    test('refuses a write that would file two voices under one label', () {
      // The write keys the block by label, so letting this through would drop
      // bm_santa from the file over an edit that never mentioned it. Kokoro
      // ships three "Santa"s and the README tells users to copy that model into
      // their overlay, so this is reachable on a shipped file.
      f.writeModel('kokoro', const {
        'id': 'hexgrad/kokoro-82m',
        'voices': {
          'Emma': {'id': 'bf_emma'},
          'bm_santa': {'name': 'Santa', 'id': 'bm_santa'},
          'am_santa': {'name': 'Santa', 'id': 'am_santa'},
        },
      });
      final edit = f.store.setDefaultVoice('kokoro', 'bm_santa');
      expect(edit.ok, isFalse);
      expect(edit.error, contains('Santa'));
      expect(f.store.hasOverlayModel('kokoro'), isFalse);
    });

    test('renaming one of the duplicates is what unblocks the edit', () {
      f.writeModel('kokoro', const {
        'id': 'hexgrad/kokoro-82m',
        'voices': {
          'Emma': {'id': 'bf_emma'},
          'bm_santa': {'name': 'Santa', 'id': 'bm_santa'},
          'am_santa': {'name': 'Santa', 'id': 'am_santa'},
        },
      });
      expect(f.store.setDefaultVoice('kokoro', 'bm_santa').ok, isFalse);

      final rename = f.store.saveVoice(
        'kokoro',
        key: 'am_santa',
        label: 'Santa (male)',
        id: 'am_santa',
      );
      expect(rename.ok, isTrue);

      // The write keys the block by label, so the row is now filed under its
      // name rather than its id -- which is the whole point of normalising.
      final voices = f.readOverlay('kokoro')['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['Emma', 'Santa', 'Santa (male)']);
      expect(f.store.setDefaultVoice('kokoro', 'Santa').ok, isTrue);
      expect(f.readOverlay('kokoro')['default_voice'], 'Santa');
    });
  });

  group('default_voice is carried, never dropped', () {
    // `default_voice` is a key into the same map a write rewrites, and
    // VoiceConfig.resolveVoice also accepts a bare id. An edit to an unrelated
    // voice must therefore never remove a value it could not resolve: losing it
    // un-defaults the model, after which defaultVoiceFor throws and the model
    // cannot be selected at all.

    test('survives a removal of an unrelated voice', () {
      expect(f.store.removeVoice('fish', 'Bob').ok, isTrue);
      expect(f.readOverlay('fish')['default_voice'], 'Alice');
    });

    test('survives an edit to an unrelated voice', () {
      expect(
        f.store.saveVoice('fish', key: 'Bob', label: 'Robert', id: 'bbb').ok,
        isTrue,
      );
      expect(f.readOverlay('fish')['default_voice'], 'Alice');
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
      // Normalised to the label the write files it under, which still resolves.
      expect(f.readOverlay('kokoro')['default_voice'], 'Emma');
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
      expect(f.store.removeVoice('fish', 'Bob').ok, isTrue);
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
      expect(f.store.removeVoice('fish', 'Alice').ok, isTrue);
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
      expect(f.store.removeVoice('fish', 'Bob').ok, isTrue);
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
    test('folds an explicit name into the key', () {
      f.writeModel('kokoro', const {
        'id': 'hexgrad/kokoro-82m',
        'default_voice': 'Emma',
        'voices': {
          'bf_emma': {'name': 'Emma'},
        },
      });
      f.store.saveVoice(
        'kokoro',
        key: 'bf_emma',
        label: 'Emma',
        id: 'bf_emma',
      );
      final json = f.readOverlay('kokoro');
      final voices = json['voices'] as Map<String, dynamic>;
      expect(voices.keys, ['Emma']);
      expect(voices['Emma'], {'id': 'bf_emma'});
      expect(json['default_voice'], 'Emma');
    });

    test('expands a string shorthand to the explicit id form', () {
      f.writeModel('gemini', const {
        'id': 'google/gemini',
        'voices': {'Charon': 'Charon'},
      });
      f.store.saveVoice('gemini', key: 'Charon', label: 'Charon', id: 'Charon');
      final voices = f.readOverlay('gemini')['voices'] as Map<String, dynamic>;
      expect(voices['Charon'], {'id': 'Charon'});
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
      expect(voices['Emma'], {'id': 'bf_emma', 'gender': 'female'});
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
      f.store.saveVoice(
        'kokoro',
        key: 'bf_emma',
        label: 'Emma',
        id: 'bf_emma',
      );
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
      final voice = cfg.voices['fish']!['Custom']!;
      expect(voice.id, 'ccc');
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
