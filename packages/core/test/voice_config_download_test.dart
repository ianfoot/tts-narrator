import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/voice_config_download.dart';

/// A git tree response body, as the API returns it.
String _tree(List<(String, String)> entries) => jsonEncode({
  'sha': 'abc123',
  'truncated': false,
  'tree': [
    for (final (path, type) in entries)
      {'path': path, 'type': type, 'mode': '100644', 'size': 1},
  ],
});

void main() {
  group('voiceConfigPathsFromTree', () {
    test('takes the voice-config json files, relative to that directory', () {
      // Relative, because the destination is a config directory whose own layout
      // is the reader's business: the repository's directory name is the
      // downloader's, and nothing above it should leak into a local path.
      final paths = voiceConfigPathsFromTree(
        _tree([
          ('voice-config/config.json', 'blob'),
          ('voice-config/providers/openrouter.json', 'blob'),
          ('voice-config/models/fish.json', 'blob'),
          ('voice-config/models/macos/kokoro_local.json', 'blob'),
        ]),
      );
      expect(paths, [
        'config.json',
        'models/fish.json',
        'models/macos/kokoro_local.json',
        'providers/openrouter.json',
      ]);
    });

    test('ignores directories, which are not files to download', () {
      // The tree lists directories as entries too. Downloading one would write
      // whatever the raw endpoint answered with, in place of a directory.
      final paths = voiceConfigPathsFromTree(
        _tree([
          ('voice-config/models', 'tree'),
          ('voice-config/models/macos', 'tree'),
          ('voice-config/models/fish.json', 'blob'),
        ]),
      );
      expect(paths, ['models/fish.json']);
    });

    test('ignores anything outside voice-config, and non-json files', () {
      // The tree is the whole repository, not a subdirectory listing, so the
      // filter is what makes the answer a voice config.
      final paths = voiceConfigPathsFromTree(
        _tree([
          ('README.md', 'blob'),
          ('voice-config/README.md', 'blob'),
          ('voice-config/models/fish.json', 'blob'),
          ('packages/core/lib/main.dart', 'blob'),
        ]),
      );
      expect(paths, ['models/fish.json']);
    });

    test('a tree with no voice-config files yields nothing', () {
      expect(voiceConfigPathsFromTree(_tree([('README.md', 'blob')])), isEmpty);
    });

    test('rejects a body that is not a tree response', () {
      expect(
        () => voiceConfigPathsFromTree('[]'),
        throwsFormatException,
      );
      expect(
        () => voiceConfigPathsFromTree('{"sha":"abc"}'),
        throwsFormatException,
      );
    });
  });

  group('fetchVoiceConfigPaths', () {
    HttpClient Function() client() =>
        () => HttpClient()..connectionTimeout = const Duration(seconds: 5);

    test('asks the git tree endpoint and parses the answer', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requested = <String>[];
      final serverDone = server.listen((request) async {
        requested.add('${request.uri.path}?${request.uri.query}');
        request.response
          ..statusCode = 200
          ..write(
            _tree([
              ('voice-config/config.json', 'blob'),
              ('voice-config/models/fish.json', 'blob'),
            ]),
          );
        await request.response.close();
      });
      final base = 'http://${server.address.address}:${server.port}';
      try {
        final paths = await fetchVoiceConfigPaths(
          clientFactory: client(),
          apiUrl: base,
          branch: 'test-branch',
        );
        expect(paths, ['config.json', 'models/fish.json']);
        // One request, and it names the branch: the recursive tree is the whole
        // point, since walking the contents API costs one call per directory.
        expect(requested, hasLength(1));
        expect(requested.single, contains('/git/trees/test-branch'));
        expect(requested.single, contains('recursive=1'));
        expect(requested.single, contains('ianfoot/tts-narrator'));
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });

    test('throws on a non-200 response, so the caller can fall back', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverDone = server.listen((request) async {
        // 403 is what an unauthenticated caller gets once it has spent the
        // hourly rate limit; treating that as fatal would leave a first run with
        // no config at all rather than with the one it already has.
        request.response.statusCode = 403;
        await request.response.close();
      });
      final base = 'http://${server.address.address}:${server.port}';
      try {
        await expectLater(
          fetchVoiceConfigPaths(
            clientFactory: client(),
            apiUrl: base,
          ),
          throwsA(isA<HttpException>()),
        );
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });
  });

  group('downloadVoiceConfigFiles', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tts_download_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('downloads the paths into the subdirectories they name', () async {
      // A platform model has to land in its platform's directory: the loader
      // reads it from there, so flattening it would make a macOS-only model
      // invisible on macOS.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requested = <String>[];
      final serverDone = server.listen((request) async {
        requested.add(request.uri.path);
        request.response
          ..statusCode = 200
          ..write('{}');
        await request.response.close();
      });
      try {
        await downloadVoiceConfigFiles(
          dir.path,
          paths: [
            'models/fish.json',
            'models/macos/kokoro_local.json',
            'providers/openrouter.json',
          ],
          clientFactory: () =>
              HttpClient()..connectionTimeout = const Duration(seconds: 5),
          repoUrl: 'http://${server.address.address}:${server.port}',
        );
        // config.json is fetched whether or not the tree named it: its absence
        // is what marks a directory as not yet a voice config.
        expect(File('${dir.path}/config.json').existsSync(), isTrue);
        expect(File('${dir.path}/models/fish.json').existsSync(), isTrue);
        expect(
          File('${dir.path}/models/macos/kokoro_local.json').existsSync(),
          isTrue,
        );
        expect(
          File('${dir.path}/providers/openrouter.json').existsSync(),
          isTrue,
        );
        // The remote paths keep the subdirectory split but are always
        // forward-slashed, which is what lets one path list serve Windows.
        expect(
          requested,
          containsAll([
            endsWith('/voice-config/config.json'),
            endsWith('/voice-config/providers/openrouter.json'),
            endsWith('/voice-config/models/fish.json'),
            endsWith('/voice-config/models/macos/kokoro_local.json'),
          ]),
        );
        expect(
          requested.any((path) => path.contains(r'\')),
          isFalse,
          reason: 'remote paths must not carry local separators',
        );
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });

    test('does not re-download existing files', () async {
      // The user's own edits live in user/, so the downloaded layer is
      // disposable — but refetching it on every launch would be a request per
      // file against a rate limit nothing here holds a token for.
      File('${dir.path}/config.json').writeAsStringSync('{}');
      File('${dir.path}/models/fish.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{}');
      File('${dir.path}/providers/openrouter.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{}');
      var hits = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverDone = server.listen((request) async {
        hits++;
        request.response
          ..statusCode = 200
          ..write('{}');
        await request.response.close();
      });
      try {
        await downloadVoiceConfigFiles(
          dir.path,
          paths: ['models/fish.json', 'providers/openrouter.json'],
          // Without this the guard would silently fall through to a live
          // fetch of the public repo instead of failing the test.
          repoUrl: 'http://${server.address.address}:${server.port}',
          clientFactory: () =>
              HttpClient()..connectionTimeout = const Duration(seconds: 5),
        );
        expect(hits, 0);
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });

    test('overwrite replaces an existing file, which is how a re-sync picks '
        'up a model added since the last run', () async {
      File('${dir.path}/models/fish.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"id":"old"}');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverDone = server.listen((request) async {
        request.response
          ..statusCode = 200
          ..write('{"id":"new"}');
        await request.response.close();
      });
      try {
        await downloadVoiceConfigFiles(
          dir.path,
          paths: ['models/fish.json'],
          overwrite: true,
          repoUrl: 'http://${server.address.address}:${server.port}',
          clientFactory: () =>
              HttpClient()..connectionTimeout = const Duration(seconds: 5),
        );
        expect(
          File('${dir.path}/models/fish.json').readAsStringSync(),
          '{"id":"new"}',
        );
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });

    test('a failing file does not stop the rest', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverDone = server.listen((request) async {
        if (request.uri.path.endsWith('fish.json')) {
          request.response.statusCode = 500;
        } else {
          request.response
            ..statusCode = 200
            ..write('{}');
        }
        await request.response.close();
      });
      try {
        await downloadVoiceConfigFiles(
          dir.path,
          paths: ['models/fish.json', 'models/kokoro.json'],
          repoUrl: 'http://${server.address.address}:${server.port}',
          clientFactory: () =>
              HttpClient()..connectionTimeout = const Duration(seconds: 5),
        );
        expect(File('${dir.path}/models/fish.json').existsSync(), isFalse);
        expect(File('${dir.path}/models/kokoro.json').existsSync(), isTrue);
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });
  });
}