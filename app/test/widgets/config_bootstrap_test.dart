import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator/main.dart';

import '../support/l10n_test_support.dart';

/// The whole of `voice-config/` as the tree API reports it: the marker, the
/// providers, and every model with the platform it belongs to.
const _linuxIndex = <String>[
  'config.json',
  'providers/alpha.json',
  'models/fish.json',
  'models/gemini.json',
  'models/kokoro.json',
];

const _macosIndex = <String>[
  'config.json',
  'providers/alpha.json',
  'providers/local.json',
  'models/fish.json',
  'models/gemini.json',
  'models/kokoro.json',
  'models/macos/kokoro_local.json',
];

void main() {
  SharedPreferences.setMockInitialValues({});

  group('ConfigBootstrap first-run dialog', () {
    late String tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('test_config_').path;
    });

    tearDown(() {
      Directory(tempDir).deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });

    Future<void> pumpBootstrap(
      WidgetTester tester, {
      VoiceConfigDownloader? downloader,
      Future<List<String>?> Function()? indexLoader,
      String? repoUrl,
    }) async {
      await tester.pumpWidget(
        BootstrapApp(
          configDir: tempDir,
          prefs: await SharedPreferences.getInstance(),
          downloader: downloader,
          indexLoader: indexLoader,
          repoUrl: repoUrl,
        ),
      );
    }

    testWidgets('shows confirmation dialog when config files missing', (
      tester,
    ) async {
      await pumpBootstrap(tester, indexLoader: () async => _linuxIndex);

      await tester.pumpAndSettle();

      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsOneWidget);
      expect(find.text(testL10n.gui_bootstrap_notNow), findsOneWidget);
      expect(find.text(testL10n.gui_bootstrap_download), findsOneWidget);
    });

    testWidgets('shows AppRoot when config files exist', (tester) async {
      File('$tempDir/config.json').writeAsStringSync('{}');
      File('$tempDir/providers/alpha.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{}');
      File('$tempDir/models/fish.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{}');

      await pumpBootstrap(tester, indexLoader: () async => _linuxIndex);
      await tester.pumpAndSettle();

      // No dialog, no spinner — straight to the app.
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('shows a spinner during a confirmed download', (tester) async {
      final gate = Completer<void>();
      final calls = <(String, List<String>)>[];
      Future<void> downloader(String configDir, List<String> paths) async {
        calls.add((configDir, paths));
        await gate.future;
      }

      await pumpBootstrap(
        tester,
        downloader: downloader,
        indexLoader: () async => _linuxIndex,
      );

      // Dialog is up; confirm the download.
      await tester.pumpAndSettle();
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsOneWidget);
      await tester.tap(find.text(testL10n.gui_bootstrap_download));
      // The downloader is gated, so pump explicit frames (pumpAndSettle would
      // wait forever on the pending future).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The downloader is gated, so the spinner stays visible.
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text(testL10n.gui_bootstrap_downloading), findsOneWidget);

      // Releasing the downloader lands the app.
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsNothing);
      expect(calls.single.$1, tempDir);
      expect(calls.single.$2, _linuxIndex);
    });

    testWidgets('skipping the download proceeds to the app', (tester) async {
      var downloaded = false;
      Future<void> downloader(String configDir, List<String> paths) async {
        downloaded = true;
      }

      await pumpBootstrap(
        tester,
        downloader: downloader,
        indexLoader: () async => _linuxIndex,
      );

      await tester.pumpAndSettle();
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsOneWidget);
      await tester.tap(find.text(testL10n.gui_bootstrap_notNow));
      await tester.pumpAndSettle();

      expect(downloaded, isFalse);
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsNothing);
    });

    testWidgets('the dialog names the models, not the providers', (
      tester,
    ) async {
      // Providers travel in the same list as models, so the copy has to pick
      // the models out of it.
      await pumpBootstrap(tester, indexLoader: () async => _macosIndex);
      await tester.pumpAndSettle();

      expect(find.textContaining('Kokoro Local'), findsOneWidget);
      expect(find.textContaining('Alpha'), findsNothing);
    });

    testWidgets('entire flow: index drives dialog, download lands on disk, '
        'relaunch skips straight to the app', (tester) async {
      // Partial state: two starters present, marker + fish.json missing
      // -> the dialog must appear listing the indexed starters.
      File('$tempDir/models/gemini.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{}');
      File('$tempDir/models/kokoro.json').writeAsStringSync('{}');

      // Downloader mirrors downloadVoiceConfigFiles semantics: every path keeps
      // the subdirectory it was indexed under.
      Future<void> downloader(String configDir, List<String> paths) async {
        File('$configDir/config.json').writeAsStringSync('{}');
        for (final path in paths.where((p) => p != 'config.json')) {
          File('$configDir/$path')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('{}');
        }
      }

      await pumpBootstrap(
        tester,
        downloader: downloader,
        indexLoader: () async => _linuxIndex,
      );
      await tester.pumpAndSettle();

      // The index names the starters for the dialog copy.
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsOneWidget);
      expect(find.textContaining('Fish, Gemini, Kokoro'), findsOneWidget);

      await tester.tap(find.text(testL10n.gui_bootstrap_download));
      await tester.pumpAndSettle();

      // The GUI download actually wrote the files.
      expect(File('$tempDir/config.json').existsSync(), isTrue);
      expect(File('$tempDir/providers/alpha.json').existsSync(), isTrue);
      expect(File('$tempDir/models/fish.json').existsSync(), isTrue);

      // A fresh bootstrap sees a complete config dir and skips the dialog.
      await pumpBootstrap(
        tester,
        downloader: downloader,
        indexLoader: () async => _linuxIndex,
      );
      await tester.pumpAndSettle();
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('a platform-specific starter keeps its subdirectory on disk', (
      tester,
    ) async {
      // The whole reason a model sits in models/macos/ is that only macOS gets
      // it, so the download has to place it there rather than flatten it.
      Future<void> downloader(String configDir, List<String> paths) async {
        File('$configDir/config.json').writeAsStringSync('{}');
        for (final path in paths.where((p) => p != 'config.json')) {
          File('$configDir/$path')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('{}');
        }
      }

      await pumpBootstrap(
        tester,
        downloader: downloader,
        indexLoader: () async => _macosIndex,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(testL10n.gui_bootstrap_download));
      await tester.pumpAndSettle();

      expect(
        File('$tempDir/models/macos/kokoro_local.json').existsSync(),
        isTrue,
      );
      expect(File('$tempDir/models/kokoro_local.json').existsSync(), isFalse);
    });

    testWidgets('an unreachable index still offers the built-in starters', (
      tester,
    ) async {
      // No network, no cached index: the prompt must still name what it would
      // fetch rather than degrade to an empty list.
      await pumpBootstrap(tester, indexLoader: () async => null);
      await tester.pumpAndSettle();

      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsOneWidget);
      expect(find.textContaining('Fish, Gemini, Kokoro'), findsOneWidget);
    });

    testWidgets('with no downloader injected, the real download runs and lands '
        'the whole config', (tester) async {
      // Every other test here injects `downloader`, so the branch a real first
      // run takes — the one that reaches `downloadVoiceConfigFiles` — was never
      // executed. It compiled and passed 312 tests while throwing
      // NoSuchMethodError on the app's own first run, because that function's
      // signature did not match the seam's and the call was dispatched
      // dynamically. Nothing is injected here but a loopback repoUrl, so this
      // exercises the real download end to end.
      final requested = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverDone = server.listen((request) async {
        requested.add(request.uri.path);
        request.response
          ..statusCode = 200
          ..write('{}');
        await request.response.close();
      });

      try {
        await pumpBootstrap(
          tester,
          indexLoader: () async => _macosIndex,
          repoUrl: 'http://${server.address.address}:${server.port}',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(testL10n.gui_bootstrap_download));
        await tester.pumpAndSettle();

        // Nothing escaped the download: this is the line the bug failed on.
        expect(tester.takeException(), isNull);

        expect(File('$tempDir/config.json').existsSync(), isTrue);
        expect(File('$tempDir/providers/alpha.json').existsSync(), isTrue);
        expect(File('$tempDir/models/fish.json').existsSync(), isTrue);
        // A macOS-only model stays in its platform directory, or the loader would
        // not find it on the one platform it is served on.
        expect(
          File('$tempDir/models/macos/kokoro_local.json').existsSync(),
          isTrue,
        );
        // Every indexed path was actually asked for, subdirectory included.
        expect(
          requested,
          containsAll([
            endsWith('/voice-config/config.json'),
            endsWith('/voice-config/providers/alpha.json'),
            endsWith('/voice-config/models/fish.json'),
            endsWith('/voice-config/models/macos/kokoro_local.json'),
          ]),
        );
        expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsNothing);
      } finally {
        await serverDone.cancel();
        await server.close(force: true);
      }
    });
  });
}