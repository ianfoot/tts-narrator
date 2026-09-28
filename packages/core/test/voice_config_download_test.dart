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
      expect(
        manifest.filesFor('macos'),
        ['fish.json', 'kokoro.json', 'mlx_kokoro.json'],
      );
      expect(manifest.filesFor('linux'), ['fish.json', 'kokoro.json']);
      expect(manifest.hasPlatform('macos'), isTrue);
      expect(manifest.hasPlatform('windows'), isFalse);
    });

    test('unknown platform yields an empty list', () {
      final manifest = ManifestVoiceConfig.fromJson({
        'platforms': {'macos': ['fish.json']},
      });
      expect(manifest.filesFor('linux'), isEmpty);
      expect(manifest.hasPlatform('linux'), isFalse);
    });

    test('rejects a missing platforms key', () {
      expect(
        () => ManifestVoiceConfig.fromJson(const {}),
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
  });

  group('fetchVoiceConfigManifest', () {
    HttpClient Function() client(HttpServer server) => () =>
        HttpClient()..connectionTimeout = const Duration(seconds: 5);
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

    test('downloads config.json plus the requested files', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requested = <String>[];
      final served = <String, String>{};
      final serverDone = server.listen((request) async {
        final name = request.uri.pathSegments.last;
        requested.add(name);
        served[name] = '{"id": "$name"}';
        request.response
          ..statusCode = 200
          ..write(served[name]);
        await request.response.close();
      });
      try {
        await downloadVoiceConfigFiles(
          dir.path,
          files: ['fish.json', 'mlx_kokoro.json'],
          clientFactory: () => HttpClient()
            ..connectionTimeout = const Duration(seconds: 5),
          repoUrl: 'http://${server.address.address}:${server.port}',
        );
        expect(File('${dir.path}/config.json').existsSync(), isTrue);
        expect(File('${dir.path}/fish.json').existsSync(), isTrue);
        expect(File('${dir.path}/mlx_kokoro.json').existsSync(), isTrue);
        expect(requested, containsAll(['config.json', 'fish.json', 'mlx_kokoro.json']));
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });

    test('does not re-download existing files', () async {
      File('${dir.path}/config.json').writeAsStringSync('{}');
      File('${dir.path}/fish.json').writeAsStringSync('{}');
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
          clientFactory: () => HttpClient()
            ..connectionTimeout = const Duration(seconds: 5),
        );
        expect(hits, 0);
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });
  });
}