import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Guards the config files this repository actually ships.
///
/// Every other test in this package builds its own fixture, so nothing else
/// would notice a typo in `voice-config/`, a `default_voice` pointing at a voice
/// that is not in the same file, or a manifest naming a starter file that does
/// not exist. Those are the states a user meets on first launch, and they are
/// invisible to the rest of the suite: a fixture that hand-sets
/// `voices_editable: true` passes whether or not the shipped file says so.
///
/// This reads the real directory, so it fails at the source rather than leaving
/// the break to be found by running the app.
///
/// This is schema validation only. It deliberately does not assert policy (which
/// model is editable, which format is the default) or vendor behaviour (what a
/// backend actually serves), because neither can be checked without pinning the
/// file to a value that changes the moment a model is added. Adding a model to an
/// existing provider requires no change here.
void main() {
  final shipped = _findShippedConfig();

  group('the shipped config directory', () {
    test('is in the repository, not left to a fixture', () {
      expect(
        shipped.path,
        endsWith('voice-config'),
        reason: 'expected to walk up from the package root to voice-config/',
      );
    });

    test('every model and provider file parses as a JSON object', () {
      for (final file in shipped.allConfigFiles) {
        final decoded = jsonDecode(file.readAsStringSync());
        expect(
          decoded,
          isA<Map<String, dynamic>>(),
          reason: '${file.path} must be a JSON object',
        );
      }
    });

    test('loads through the real loader with no warnings at all', () {
      final (config, warnings) = loadVoiceConfig(shipped.path);
      expect(warnings, isEmpty);
      expect(config.models, isNotEmpty);
    });
  });

  group('the shipped manifest', () {
    late ManifestVoiceConfig manifest;

    setUp(() {
      manifest = ManifestVoiceConfig.fromJson(
        jsonDecode(shipped.manifest.readAsStringSync()) as Map<String, dynamic>,
      );
    });

    test('names a starter file that exists, for every platform', () {
      for (final platform in const ['macos', 'linux', 'windows']) {
        expect(
          manifest.hasPlatform(platform),
          isTrue,
          reason: '$platform is a shipped platform',
        );
        for (final name in manifest.filesFor(platform)) {
          expect(
            File('${shipped.path}/models/$name').existsSync(),
            isTrue,
            reason: 'manifest lists $name for $platform but the file is absent',
          );
        }
      }
    });

    test('names a provider file that exists', () {
      for (final name in manifest.providers) {
        expect(
          File('${shipped.path}/providers/$name').existsSync(),
          isTrue,
          reason: 'manifest lists provider $name but the file is absent',
        );
      }
    });
  });

  group('the shipped model files', () {
    test('every default_voice names a voice in its own file', () {
      // The failure this guards against is not cosmetic: defaultVoiceFor throws
      // for a model whose default does not resolve, and a model that throws is
      // a model the user cannot select at all. The loader accepts any non-empty
      // string here, so this is the only place that checks it.
      for (final file in shipped.modelFiles) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final defaultVoice = json['default_voice'];
        if (defaultVoice == null) continue;
        expect(defaultVoice, isA<String>(), reason: file.path);
        final matches = _voiceEntriesOf(json).where(
          (entry) =>
              entry.$1 == defaultVoice ||
              voiceFromEntry(entry.$1, entry.$2).voice?.id == defaultVoice,
        );
        expect(
          matches,
          isNotEmpty,
          reason:
              '${file.path} defaults to "$defaultVoice", which is not one of '
              'its own voices',
        );
      }
    });

    test('a model that sends a voice lists resolvable, non-duplicate voices', () {
      // Two halves of one invariant, because both are promises the request
      // depends on. A model that takes a voice id must offer at least one and
      // they must be addressable, or the picker is empty and defaultVoiceFor
      // throws. A model that writes its voice from prose instead sends no id at
      // all, so listing voices would only invent rows the request cannot use.
      for (final file in shipped.modelFiles) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final voices = _voiceEntriesOf(json);
        if (json['sends_voice'] == false) {
          expect(
            voices,
            isEmpty,
            reason:
                '${file.path} sends no voice id, so its ${voices.length} '
                'listed voice(s) could never be selected',
          );
          continue;
        }
        expect(voices, isNotEmpty, reason: '${file.path} has no voices');
        final ids = <String>[];
        for (final entry in voices) {
          final decoded = voiceFromEntry(entry.$1, entry.$2);
          expect(
            decoded.voice,
            isNotNull,
            reason: '${file.path} voice "${entry.$1}": ${decoded.problem}',
          );
          ids.add(decoded.voice!.id);
        }
        // A repeated id silently collapses: the picker dedupes on id, so one
        // voice would vanish without a trace.
        expect(
          ids.toSet(),
          hasLength(ids.length),
          reason: '${file.path} repeats an id, so one voice would vanish',
        );
      }
    });
  });
}

/// The repository's `voice-config/` directory.
class _ShippedConfig {
  _ShippedConfig(this.path) : manifest = File('$path/manifest.json');

  final String path;

  /// The manifest naming the starter files to fetch.
  final File manifest;

  List<File> get modelFiles => _filesIn(kVoiceConfigModelsDir);

  List<File> get providerFiles => _filesIn(kVoiceConfigProvidersDir);

  List<File> get allConfigFiles => [...modelFiles, ...providerFiles];

  List<File> _filesIn(String subdir) =>
      Directory('$path/$subdir')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
}

/// One `voices` entry as `(key, raw value)` pairs, from either accepted shape.
///
/// Reading the raw JSON rather than the parsed config is the point of these
/// tests, and a model may write its `voices` as an object keyed by label or as a
/// bare list of ids. Handing both back as pairs lets one assertion cover both,
/// instead of every check here silently covering only whichever shape the
/// shipped files happened to use.
List<(String, Object?)> _voiceEntriesOf(Map<String, dynamic> json) {
  final raw = json['voices'];
  if (raw is Map<String, dynamic>) {
    return raw.entries.map((e) => (e.key, e.value)).toList();
  }
  // A list entry is its own key, so the pair repeats one value twice. A
  // non-string element keeps its value, so voiceFromEntry can report why the
  // entry was rejected rather than the test crashing on the cast first.
  if (raw is List) {
    return raw
        .map((id) => (id is String ? id : '$id', id))
        .cast<(String, Object?)>()
        .toList();
  }
  return const [];
}

/// Walks up from the package root to the directory holding `voice-config/`.
///
/// Searching rather than hard-coding `../..` keeps the test honest if the
/// layout ever moves, and failing loudly if the directory is not found keeps it
/// from quietly passing on an empty set.
_ShippedConfig _findShippedConfig() {
  var dir = Directory.current.absolute;
  while (true) {
    final candidate = Directory('${dir.path}/voice-config');
    if (candidate.existsSync()) return _ShippedConfig(candidate.path);
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'No voice-config/ directory found above ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}