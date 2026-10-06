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
      expect(config.models.keys, hasLength(5));
      expect(config.providers.keys, ['openrouter', 'local']);
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

    test('offers the mlx-audio models only where a local server can exist', () {
      // Both are served by mlx-audio, which needs Apple Silicon, so a Linux or
      // Windows install must never download a model whose only provider is
      // localhost.
      for (final name in const [
        'kokoro_local.json',
        'qwen3_voicedesign.json',
      ]) {
        expect(manifest.filesFor('macos'), contains(name));
        expect(manifest.filesFor('linux'), isNot(contains(name)));
        expect(manifest.filesFor('windows'), isNot(contains(name)));
      }
    });
  });

  group('the shipped model files', () {
    test('every default_voice names a voice in its own file', () {
      // The failure this guards against is not cosmetic: defaultVoiceFor throws
      // for a model whose default does not resolve, and a model that throws is
      // a model the user cannot select at all.
      for (final file in shipped.modelFiles) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final defaultVoice = json['default_voice'];
        if (defaultVoice == null) continue;
        expect(defaultVoice, isA<String>(), reason: file.path);
        final voices = json['voices'] as Map<String, dynamic>;
        final matches = voices.entries.where(
          (entry) =>
              entry.key == defaultVoice ||
              voiceFromEntry(entry.key, entry.value).voice?.id == defaultVoice,
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
        final voices = json['voices'] as Map<String, dynamic>?;
        if (json['sends_voice'] == false) {
          expect(
            voices,
            anyOf(isNull, isEmpty),
            reason:
                '${file.path} sends no voice id, so its ${voices?.length} '
                'listed voice(s) could never be selected',
          );
          continue;
        }
        expect(voices, isNotEmpty, reason: '${file.path} has no voices');
        final ids = <String>[];
        for (final entry in voices!.entries) {
          final decoded = voiceFromEntry(entry.key, entry.value);
          expect(
            decoded.voice,
            isNotNull,
            reason: '${file.path} voice "${entry.key}": ${decoded.problem}',
          );
          ids.add(decoded.voice!.id);
        }
        expect(
          ids.toSet(),
          hasLength(ids.length),
          reason: '${file.path} repeats an id, so one voice would vanish',
        );
      }
    });

    test('every model declares its formats explicitly, as mp3 or wav', () {
      // The vocabulary the app offers the user is exactly mp3 and wav, so a
      // shipped file that omits the list falls back to the default and one that
      // names a retired format is rewritten behind the user's back. Reading the
      // raw JSON rather than the parsed profile is the point: it also catches a
      // file still using the retired single "format" key.
      for (final file in shipped.modelFiles) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final formats = json['formats'];
        expect(
          formats,
          isA<List<Object?>>(),
          reason: '${file.path} must list its "formats"',
        );
        expect(
          formats,
          isNotEmpty,
          reason: '${file.path} offers no output format at all',
        );
        for (final format in formats! as List<Object?>) {
          expect(
            format,
            anyOf('mp3', 'wav'),
            reason:
                '${file.path} offers "$format", which is not a user '
                'selectable format',
          );
        }
        expect(
          json['format'],
          isNull,
          reason: '${file.path} still uses the retired "format" key',
        );
        expect(
          json['sample_rate'],
          isNull,
          reason:
              '${file.path} still sets "sample_rate", which is no longer '
              'read or honoured',
        );
      }
    });

    test('fish is the one shipped model whose voices are editable', () {
      // Fish is where a user adds voices -- it has the long tail of them. The
      // rest describe what the model actually offers, so editing their lists in
      // the app would be a lie. Pinning it here means flipping either side is a
      // deliberate edit rather than a stray keystroke.
      final editable = <String>[];
      for (final file in shipped.modelFiles) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        if (json['voices_editable'] == true) {
          editable.add(_aliasOf(file));
        }
      }
      expect(editable, ['fish']);
      expect(
        editable.length,
        1,
        reason: 'a new editable model is a product decision, not an accident',
      );
    });

    test('kokoro is left locked, because its duplicate labels cannot be saved', () {
      // Writing any edit keys the voices block by label, and Kokoro ships three
      // voices named "Santa". If it were editable, the first save would be
      // refused with no way for the user to tell why it happened on a file they
      // never opened.
      final json = jsonDecode(
        shipped.modelFile('kokoro').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['voices_editable'], isNull);

      final labels = <String, int>{};
      for (final entry in (json['voices'] as Map<String, dynamic>).entries) {
        final decoded = voiceFromEntry(entry.key, entry.value).voice!;
        final label = decoded.name ?? entry.key;
        labels[label] = (labels[label] ?? 0) + 1;
      }
      expect(
        labels.entries.where((e) => e.value > 1).map((e) => e.key),
        isNotEmpty,
        reason: 'the reason kokoro stays locked; retest if this ever changes',
      );
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

  File modelFile(String alias) =>
      File('$path/$kVoiceConfigModelsDir/$alias.json');
}

/// The alias a model file is filed under, which is what the loader keys it by.
String _aliasOf(File file) =>
    file.uri.pathSegments.last.replaceAll('.json', '');

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
