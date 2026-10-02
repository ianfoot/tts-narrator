import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/config/voice_config_download.dart';

void main() {
  group('ManifestVoiceConfig', () {
    test('parses per-platform file lists', () {
      final manifest = ManifestVoiceConfig.fromJson({
        'platforms': {
          'macos': ['fish.json', 'kokoro.json', 'mlx_kokoro.json'],
          'linux': ['fish.json', 'kokoro.json'],
        },
      });
      expect(manifest.filesFor('macos'), [
        'fish.json',
        'kokoro.json',
        'mlx_kokoro.json',
      ]);
      expect(manifest.filesFor('linux'), ['fish.json', 'kokoro.json']);
      expect(manifest.hasPlatform('macos'), isTrue);
      expect(manifest.hasPlatform('windows'), isFalse);
    });

    test('parses a top-level providers list fetched for every platform', () {
      final manifest = ManifestVoiceConfig.fromJson({
        'providers': ['openrouter.json', 'mlx_audio.json'],
        'platforms': {
          'macos': ['fish.json'],
        },
      });
      expect(manifest.providers, ['openrouter.json', 'mlx_audio.json']);
      expect(manifest.filesFor('linux'), isEmpty);
    });

    test('unknown platform yields an empty list', () {
      final manifest = ManifestVoiceConfig.fromJson({
        'platforms': {
          'macos': ['fish.json'],
        },
      });
      expect(manifest.filesFor('linux'), isEmpty);
      expect(manifest.hasPlatform('linux'), isFalse);
    });

    test('accepts a manifest with no platforms key', () {
      final manifest = ManifestVoiceConfig.fromJson({
        'providers': ['openrouter.json'],
      });
      expect(manifest.filesFor('macos'), isEmpty);
      expect(manifest.providers, ['openrouter.json']);
    });

    test('a missing providers list yields no provider files', () {
      final manifest = ManifestVoiceConfig.fromJson({
        'platforms': {
          'macos': ['fish.json'],
        },
      });
      expect(manifest.providers, isEmpty);
    });

    test('rejects a non-list providers entry', () {
      expect(
        () => ManifestVoiceConfig.fromJson({
          'providers': {'openrouter': {}},
        }),
        throwsFormatException,
      );
    });

    test('rejects a non-list platform entry', () {
      expect(
        () => ManifestVoiceConfig.fromJson({
          'platforms': {'macos': 'fish.json'},
        }),
        throwsFormatException,
      );
    });

    test('round-trips through toJson', () {
      final manifest = ManifestVoiceConfig.fromJson({
        'providers': ['openrouter.json'],
        'platforms': {
          'macos': ['fish.json'],
        },
      });
      expect(
        ManifestVoiceConfig.fromJson(manifest.toJson()).providers,
        ['openrouter.json'],
      );
      expect(
        ManifestVoiceConfig.fromJson(manifest.toJson()).filesFor('macos'),
        ['fish.json'],
      );
    });
  });

  group('fetchVoiceConfigManifest', () {
    HttpClient Function() client(HttpServer server) =>
        () => HttpClient()..connectionTimeout = const Duration(seconds: 5);
    String repoUrl(HttpServer server) =>
        'http://${server.address.address}:${server.port}';

    test('fetches and parses the manifest from a server', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverDone = server.listen((request) async {
        request.response
          ..statusCode = 200
          ..write(
            '{"platforms":{"macos":["fish.json"],"linux":["fish.json"]}}',
          );
        await request.response.close();
      });
      try {
        final manifest = await fetchVoiceConfigManifest(
          clientFactory: client(server),
          repoUrl: repoUrl(server),
        );
        expect(manifest.filesFor('macos'), ['fish.json']);
        expect(manifest.filesFor('linux'), ['fish.json']);
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });

    test('throws on a non-200 response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverDone = server.listen((request) async {
        request.response.statusCode = 404;
        await request.response.close();
      });
      try {
        await expectLater(
          fetchVoiceConfigManifest(
            clientFactory: client(server),
            repoUrl: repoUrl(server),
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

    test('downloads create the directory', () {
      downloadVoiceConfigFiles(dir.path);
      expect(Directory(dir.path).existsSync(), isTrue);
    });

    test('downloads config.json plus the requested files into their subdirs',
        () async {
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
          files: ['fish.json', 'mlx_kokoro.json'],
          providers: ['openrouter.json'],
          clientFactory: () =>
              HttpClient()..connectionTimeout = const Duration(seconds: 5),
          repoUrl: 'http://${server.address.address}:${server.port}',
        );
        expect(File('${dir.path}/config.json').existsSync(), isTrue);
        expect(File('${dir.path}/providers/openrouter.json').existsSync(),
            isTrue);
        expect(File('${dir.path}/models/fish.json').existsSync(), isTrue);
        expect(
          File('${dir.path}/models/mlx_kokoro.json').existsSync(),
          isTrue,
        );
        // The remote paths keep the subdirectory split but are always
        // forward-slashed, which is what lets one manifest serve Windows.
        expect(
          requested,
          containsAll([
            endsWith('/voice-config/config.json'),
            endsWith('/voice-config/providers/openrouter.json'),
            endsWith('/voice-config/models/fish.json'),
            endsWith('/voice-config/models/mlx_kokoro.json'),
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
          files: ['fish.json'],
          providers: ['openrouter.json'],
          clientFactory: () =>
              HttpClient()..connectionTimeout = const Duration(seconds: 5),
        );
        expect(hits, 0);
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });
  });
}
