import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator/main.dart';
import 'package:tts_narrator/src/gui/platform/widgets/platform_activity_indicator.dart';

void main() {
  SharedPreferences.setMockInitialValues({});

  group('ConfigBootstrap first-run dialog', () {
    late String tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('test_config_').path;
    });

    tearDown(() {
      Directory(tempDir).deleteSync(recursive: true);
    });

    Future<void> pumpBootstrap(
      WidgetTester tester, {
      Future<void> Function(String configDir)? downloader,
    }) async {
      await tester.pumpWidget(
        BootstrapApp(
          configDir: tempDir,
          prefs: await SharedPreferences.getInstance(),
          downloader: downloader,
        ),
      );
    }

    testWidgets('shows confirmation dialog when config files missing', (
      tester,
    ) async {
      await pumpBootstrap(tester);

      await tester.pumpAndSettle();

      expect(find.text('Download Voice Configurations?'), findsOneWidget);
      expect(find.text('Not Now'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('shows AppRoot when config files exist', (tester) async {
      File('$tempDir/config.json').writeAsStringSync('{}');
      File('$tempDir/fish.json').writeAsStringSync('{}');
      File('$tempDir/gemini.json').writeAsStringSync('{}');
      File('$tempDir/kokoro.json').writeAsStringSync('{}');
      File('$tempDir/mlx_kokoro.json').writeAsStringSync('{}');

      await pumpBootstrap(tester);
      await tester.pumpAndSettle();

      // No dialog, no spinner — straight to the app.
      expect(find.text('Download Voice Configurations?'), findsNothing);
      expect(find.byType(PlatformActivityIndicator), findsNothing);
    });

    testWidgets('shows a spinner during a confirmed download', (tester) async {
      final gate = Completer<void>();
      final calls = <String>[];
      Future<void> downloader(String configDir) async {
        calls.add(configDir);
        await gate.future;
      }

      await pumpBootstrap(tester, downloader: downloader);

      // Dialog is up; confirm the download.
      await tester.pumpAndSettle();
      expect(find.text('Download Voice Configurations?'), findsOneWidget);
      await tester.tap(find.text('Download'));
      // The downloader is gated, so pump explicit frames (pumpAndSettle would
      // wait forever on the pending future).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The downloader is gated, so the spinner stays visible.
      expect(find.byType(PlatformActivityIndicator), findsOneWidget);
      expect(find.text('Downloading voice configurations...'), findsOneWidget);

      // Releasing the downloader lands the app.
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PlatformActivityIndicator), findsNothing);
      expect(find.text('Download Voice Configurations?'), findsNothing);
      expect(calls.single, tempDir);
    });

    testWidgets('skipping the download proceeds to the app', (tester) async {
      var downloaded = false;
      Future<void> downloader(String configDir) async {
        downloaded = true;
      }

      await pumpBootstrap(tester, downloader: downloader);

      await tester.pumpAndSettle();
      expect(find.text('Download Voice Configurations?'), findsOneWidget);
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();

      expect(downloaded, isFalse);
      expect(find.text('Download Voice Configurations?'), findsNothing);
    });
  });
}
