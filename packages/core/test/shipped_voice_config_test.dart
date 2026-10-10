import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Guards the config files this repository actually ships.
///
/// Every other test in this package builds its own fixture, so nothing else
/// would notice a typo in `voice-config/`, a `default_voice` pointing at a voice
/// that is not in the same file, or a model naming a provider that no longer
/// exists. Those are the states a user meets on first launch, and they are
/// invisible to the rest of the suite: a fixture that hand-sets
/// `voices_editable: true` passes whether or not the shipped file says so.
///
/// This reads the real directory, so it fails at the source rather than leaving
/// the break to be found by running the app.
///
/// This is schema validation only. It deliberately does not assert policy (which
/// model is editable, which format is the default) or vendor behaviour (what a
/// backend actually serves), because neither can be checked without pinning the
/// file to a value that changes the moment a model is added. Adding a model is
/// adding a file, and nothing here needs to change when one appears.
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

    test('every model names a provider that is shipped', () {
      // The one link between the two directories. Nothing else states it, so a
      // model naming a provider that is not there loads and then turns out to
      // serve nothing -- the warning is the only sign, and it reads as if the
      // model were at fault rather than the provider name being stale.
      for (final file in shipped.modelFiles) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final provider = json['provider'];
        expect(
          provider,
          isA<String>(),
          reason: '${file.path} must name its provider',
        );
        expect(
          shipped.providerFileNames,
          contains(provider),
          reason:
              '${file.path} names provider "$provider", which has no file in '
              '$kVoiceConfigProvidersDir/',
        );
      }
    });

    test('every provider file is reached by at least one model', () {
      // The other direction, and the reason a provider cannot be configured
      // ahead of the models it serves: an unreachable one is dead weight the
      // settings screen will happily offer.
      final named = shipped.modelFiles
          .map(
            (f) =>
                (jsonDecode(f.readAsStringSync())
                        as Map<String, dynamic>)['provider']
                    as String?,
          )
          .whereType<String>()
          .toSet();
      for (final name in shipped.providerFileNames) {
        expect(
          named,
          contains(name),
          reason: 'providers/$name.json is loaded but no model names it',
        );
      }
    });

    test('no provider file states which models it serves', () {
      // Membership moved into the model files. A leftover "models" key would be
      // read by nobody, so it would fail silently on the next edit made to it.
      for (final file in shipped.providerFiles) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(
          json.containsKey('models'),
          isFalse,
          reason:
              '${file.path} still lists models; membership belongs in the '
              'model files, by "provider"',
        );
      }
    });

    test('every models/ subdirectory is a platform tag', () {
      // A subdirectory named anything else is ignored by the loader, so a model
      // dropped into it would simply not appear -- which is what the loader's own
      // warning is for, but a typo caught here names the file that caused it.
      final modelsDir = Directory('${shipped.path}/$kVoiceConfigModelsDir');
      for (final child in modelsDir.listSync().whereType<Directory>()) {
        final name = child.path.split(Platform.pathSeparator).last;
        expect(
          kVoiceConfigPlatformTags,
          contains(name),
          reason: 'models/$name is not a platform tag',
        );
      }
    });

    test('loads through the real loader with no warnings at all', () {
      final (config, warnings) = loadVoiceConfig(shipped.path);
      expect(warnings, isEmpty);
      expect(config.models, isNotEmpty);
    });
  });

  group('the shipped config on each platform', () {
    // The directory a user has is the whole of what the repository ships, since
    // the download fetches everything in the tree; what a platform tag changes is
    // only which model files count. So a platform bug is a model file in the
    // wrong directory, and these reads are what catches one.
    for (final platform in const [
      kPlatformTagMacos,
      kPlatformTagLinux,
      kPlatformTagWindows,
    ]) {
      test('loads on $platform with no warnings at all', () {
        final (config, warnings) = loadVoiceConfig(
          shipped.path,
          platformTag: platform,
        );
        expect(
          warnings,
          isEmpty,
          reason: 'a shipped $platform config is clean',
        );
        expect(config.models, isNotEmpty, reason: 'on $platform');
      });

      test('a model in models/$platform is served only on $platform', () {
        final platformDir = Directory(
          '${shipped.path}/$kVoiceConfigModelsDir/$platform',
        );
        if (!platformDir.existsSync()) return;

        final here = loadVoiceConfig(
          shipped.path,
          platformTag: platform,
        ).$1.models.keys.toSet();
        final elsewhere = <String>{
          for (final other in kVoiceConfigPlatformTags)
            if (other != platform)
              ...loadVoiceConfig(
                shipped.path,
                platformTag: other,
              ).$1.models.keys,
        };

        for (final file in platformDir.listSync().whereType<File>()) {
          final alias = file.path
              .split(Platform.pathSeparator)
              .last
              .replaceAll('.json', '');
          expect(
            here,
            contains(alias),
            reason: 'models/$platform/$alias.json must be served on $platform',
          );
          expect(
            elsewhere,
            isNot(contains(alias)),
            reason:
                'models/$platform/$alias.json is $platform-only, so another '
                'platform must not see it',
          );
        }
      });
    }

    test('an untagged read sees every platform\'s models', () {
      // The union is for a caller inspecting the config as data; if it lost a
      // platform the settings screen and the shipped-config guards would both be
      // looking at less than the repository holds.
      final all = loadVoiceConfig(shipped.path).$1.models.keys.toSet();
      for (final platform in kVoiceConfigPlatformTags) {
        final here = loadVoiceConfig(
          shipped.path,
          platformTag: platform,
        ).$1.models.keys.toSet();
        expect(
          all,
          containsAll(here),
          reason: 'the union must include everything $platform serves',
        );
      }
    });

    test('the first provider is a hosted one, so the app opens reachable', () {
      // Precedence is derived rather than declared: the provider holding an
      // api_key sorts ahead of the ones needing a local server. If every
      // provider were local the app would open on a model it cannot reach.
      for (final platform in kVoiceConfigPlatformTags) {
        final config = loadVoiceConfig(
          shipped.path,
          platformTag: platform,
        ).$1;
        expect(config.providers, isNotEmpty, reason: 'on $platform');
        final first = config.providers.values.first;
        expect(
          first.settings,
          contains('api_key'),
          reason:
              'on $platform the first provider is "${first.name}", which has no '
              'api_key and so needs a server that may not be running',
        );
      }
    });

    test('every provider\'s models list is what its model files say', () {
      // ProviderConfig.models is gathered from the files, not read from anything,
      // so this is the check that a model file's "provider" is what decides who
      // serves it.
      for (final platform in const [kPlatformTagMacos, null]) {
        final config = loadVoiceConfig(
          shipped.path,
          platformTag: platform,
        ).$1;
        for (final provider in config.providers.values) {
          for (final alias in provider.models) {
            expect(
              config.models[alias]?.provider,
              provider.name,
              reason:
                  'provider "${provider.name}" lists $alias, which the model '
                  'file assigns elsewhere',
            );
          }
        }
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
  _ShippedConfig(this.path);

  final String path;

  /// The marker file whose presence says this is a voice config directory.
  File get registry => File('$path/$kVoiceConfigRegistryName');

  /// Every model file, at the top level and in each platform subdirectory.
  ///
  /// Walking the subdirectories is the point: a model file in `models/macos/`
  /// ships exactly as much as one in `models/`, and a scanner that stopped at the
  /// top level would quietly stop guarding the macOS-only ones.
  List<File> get modelFiles => [
    ..._filesIn(kVoiceConfigModelsDir),
    for (final sub in _subdirsOfModels())
      ..._filesIn('$kVoiceConfigModelsDir/$sub'),
  ];

  List<String> get providerFileNames => providerFiles
      .map((f) => f.path.split(Platform.pathSeparator).last)
      .map((f) => f.replaceAll('.json', ''))
      .toList()
    ..sort();

  List<File> get providerFiles => _filesIn(kVoiceConfigProvidersDir);

  List<File> get allConfigFiles => [...modelFiles, ...providerFiles];

  List<String> _subdirsOfModels() => Directory('$path/$kVoiceConfigModelsDir')
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path.split(Platform.pathSeparator).last)
      .toList()
    ..sort();

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