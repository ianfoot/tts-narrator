import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator/main.dart';
import '../support/l10n_test_support.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

final _linuxManifest = ManifestVoiceConfig.fromJson({
  'platforms': {
    'linux': ['fish.json', 'gemini.json', 'kokoro.json'],
  },
});

final _macosManifest = ManifestVoiceConfig.fromJson({
  'platforms': {
    'macos': ['fish.json', 'gemini.json', 'kokoro.json', 'mlx_kokoro.json'],
  },
});

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
      Future<void> Function(String configDir, List<String> files)? downloader,
      Future<ManifestVoiceConfig?> Function()? manifestLoader,
    }) async {
      await tester.pumpWidget(
        BootstrapApp(
          configDir: tempDir,
          prefs: await SharedPreferences.getInstance(),
          downloader: downloader,
          manifestLoader: manifestLoader,
        ),
      );
    }

    // Runs [body] under a target-platform override, resetting it before the
    // binding's invariant check (which runs before test teardowns).
    Future<void> withPlatform(
      TargetPlatform target,
      Future<void> Function() body,
    ) async {
      debugDefaultTargetPlatformOverride = target;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('shows confirmation dialog when config files missing', (
      tester,
    ) async {
      await pumpBootstrap(tester, manifestLoader: () async => _linuxManifest);

      await tester.pumpAndSettle();

      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsOneWidget);
      expect(find.text(testL10n.gui_bootstrap_notNow), findsOneWidget);
      expect(find.text(testL10n.gui_bootstrap_download), findsOneWidget);
    });

    testWidgets('shows AppRoot when config files exist', (tester) async {
      File('$tempDir/config.json').writeAsStringSync('{}');
      File('$tempDir/fish.json').writeAsStringSync('{}');
      File('$tempDir/gemini.json').writeAsStringSync('{}');
      File('$tempDir/kokoro.json').writeAsStringSync('{}');

      await pumpBootstrap(tester, manifestLoader: () async => _linuxManifest);
      await tester.pumpAndSettle();

      // No dialog, no spinner — straight to the app.
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('shows a spinner during a confirmed download', (tester) async {
      final gate = Completer<void>();
      final calls = <(String, List<String>)>[];
      Future<void> downloader(String configDir, List<String> files) async {
        calls.add((configDir, files));
        await gate.future;
      }

      await pumpBootstrap(
        tester,
        downloader: downloader,
        manifestLoader: () async => _linuxManifest,
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
      expect(calls.single.$2, ['fish.json', 'gemini.json', 'kokoro.json']);
    });

    testWidgets('skipping the download proceeds to the app', (tester) async {
      var downloaded = false;
      Future<void> downloader(String configDir, List<String> files) async {
        downloaded = true;
      }

      await pumpBootstrap(
        tester,
        downloader: downloader,
        manifestLoader: () async => _linuxManifest,
      );

      await tester.pumpAndSettle();
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsOneWidget);
      await tester.tap(find.text(testL10n.gui_bootstrap_notNow));
      await tester.pumpAndSettle();

      expect(downloaded, isFalse);
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsNothing);
    });

    testWidgets('on macOS the dialog lists the MLX Kokoro starter', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.macOS, () async {
        await pumpBootstrap(tester, manifestLoader: () async => _macosManifest);

        await tester.pumpAndSettle();

        expect(
          find.text(testL10n.gui_bootstrap_downloadTitle),
          findsOneWidget,
        );
        expect(find.textContaining('MLX Kokoro'), findsOneWidget);
      });
    });

    testWidgets('on Linux the dialog omits the MLX Kokoro starter', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.linux, () async {
        await pumpBootstrap(tester, manifestLoader: () async => _linuxManifest);

        await tester.pumpAndSettle();

        expect(
          find.text(testL10n.gui_bootstrap_downloadTitle),
          findsOneWidget,
        );
        expect(find.textContaining('MLX Kokoro'), findsNothing);
      });
    });

    testWidgets('entire flow: manifest drives dialog, download lands on disk, '
        'relaunch skips straight to the app', (tester) async {
      // Partial state: two starters present, config.json + fish.json missing
      // -> the dialog must appear listing the manifest starters.
      File('$tempDir/gemini.json').writeAsStringSync('{}');
      File('$tempDir/kokoro.json').writeAsStringSync('{}');

      // Downloader mirrors downloadVoiceConfigFiles semantics: config.json
      // always, plus each manifest starter.
      Future<void> downloader(String configDir, List<String> files) async {
        File('$configDir/config.json').writeAsStringSync('{}');
        for (final file in files) {
          File('$configDir/$file').writeAsStringSync('{}');
        }
      }

      await pumpBootstrap(
        tester,
        downloader: downloader,
        manifestLoader: () async => _linuxManifest,
      );
      await tester.pumpAndSettle();

      // The manifest names the starters for the dialog copy.
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsOneWidget);
      expect(find.textContaining('Fish, Gemini, Kokoro'), findsOneWidget);

      await tester.tap(find.text(testL10n.gui_bootstrap_download));
      await tester.pumpAndSettle();

      // The GUI download actually wrote the files.
      expect(File('$tempDir/config.json').existsSync(), isTrue);
      expect(File('$tempDir/fish.json').existsSync(), isTrue);

      // A fresh bootstrap sees a complete config dir and skips the dialog.
      await pumpBootstrap(
        tester,
        downloader: downloader,
        manifestLoader: () async => _linuxManifest,
      );
      await tester.pumpAndSettle();
      expect(find.text(testL10n.gui_bootstrap_downloadTitle), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });
  });
}
