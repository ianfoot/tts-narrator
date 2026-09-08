import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/editor/editor_screen.dart';
import 'package:tts_narrator/src/gui/theme/app_tokens.dart';

import '../support/spec_window.dart';

void main() {
  group('AppPalette', () {
    test('covers every spec token in both light and dark', () {
      final light = AppPalette.light;
      final dark = AppPalette.dark;
      expect(light.isDark, isFalse);
      expect(dark.isDark, isTrue);
      expect(light.accentPrimary, isNot(dark.accentPrimary));
      expect(light.accentSuccess, isNot(dark.accentSuccess));
      expect(light.accentWarning, isNot(dark.accentWarning));
      expect(light.accentError, isNot(dark.accentError));
      expect(light.bgApp, isNot(dark.bgApp));
      expect(light.bgSurface, isNot(dark.bgSurface));
      expect(light.bgSurfaceElevated, isNot(dark.bgSurfaceElevated));
      expect(light.borderSubtle, isNot(dark.borderSubtle));
      expect(light.textPrimary, isNot(dark.textPrimary));
      expect(light.textSecondary, isNot(dark.textSecondary));
      expect(light.textTertiary, isNot(dark.textTertiary));
    });

    test('spot-checks the spec hex values (spec §1)', () {
      // bg-app
      expect(AppPalette.light.bgApp, const Color(0xFFFBFBF9));
      expect(AppPalette.dark.bgApp, const Color(0xFF141416));
      // accent-primary
      expect(AppPalette.light.accentPrimary, const Color(0xFF007AFF));
      expect(AppPalette.dark.accentPrimary, const Color(0xFF0A84FF));
      // accent-success
      expect(AppPalette.light.accentSuccess, const Color(0xFF34C759));
      expect(AppPalette.dark.accentSuccess, const Color(0xFF30D158));
      // accent-warning
      expect(AppPalette.light.accentWarning, const Color(0xFFFF9500));
      expect(AppPalette.dark.accentWarning, const Color(0xFFFF9F0A));
      // accent-error
      expect(AppPalette.light.accentError, const Color(0xFFFF3B30));
      expect(AppPalette.dark.accentError, const Color(0xFFFF453A));
      // surfaces + text
      expect(AppPalette.light.bgSurface, const Color(0xFFFFFFFF));
      expect(AppPalette.dark.bgSurface, const Color(0xFF1E1E22));
      expect(AppPalette.light.bgSurfaceElevated, const Color(0xFFF2F2EE));
      expect(AppPalette.dark.bgSurfaceElevated, const Color(0xFF2A2A2E));
      expect(AppPalette.light.borderSubtle, const Color(0xFFE5E5E2));
      expect(AppPalette.dark.borderSubtle, const Color(0xFF2C2C30));
      expect(AppPalette.light.textPrimary, const Color(0xFF1C1C1E));
      expect(AppPalette.dark.textPrimary, const Color(0xFFEDEDED));
      expect(AppPalette.light.textSecondary, const Color(0xFF6E6E73));
      expect(AppPalette.dark.textSecondary, const Color(0xFF8E8E93));
      expect(AppPalette.light.textTertiary, const Color(0xFF4D4D52));
      expect(AppPalette.dark.textTertiary, const Color(0xFFADADB2));
    });

    test('of() returns the canonical palette for each brightness', () {
      expect(
        identical(AppPalette.of(Brightness.dark), AppPalette.dark),
        isTrue,
      );
      expect(
        identical(AppPalette.of(Brightness.light), AppPalette.light),
        isTrue,
      );
    });
  });

  group('resolveBrightness', () {
    test('pins the brightness for light and dark modes', () {
      expect(
        resolveBrightness(AppThemeMode.light, Brightness.dark),
        Brightness.light,
      );
      expect(
        resolveBrightness(AppThemeMode.light, Brightness.light),
        Brightness.light,
      );
      expect(
        resolveBrightness(AppThemeMode.dark, Brightness.light),
        Brightness.dark,
      );
      expect(
        resolveBrightness(AppThemeMode.dark, Brightness.dark),
        Brightness.dark,
      );
    });

    test('delegates to the system brightness in system mode', () {
      expect(
        resolveBrightness(AppThemeMode.system, Brightness.dark),
        Brightness.dark,
      );
      expect(
        resolveBrightness(AppThemeMode.system, Brightness.light),
        Brightness.light,
      );
    });
  });

  group('AppTypography', () {
    test('resolves the serif + mono family per platform', () {
      expect(AppTypography(TargetPlatform.macOS).editorSerifFamily, 'Georgia');
      expect(
        AppTypography(TargetPlatform.windows).editorSerifFamily,
        'Georgia',
      );
      expect(AppTypography(TargetPlatform.android).editorSerifFamily, 'serif');
      expect(AppTypography(TargetPlatform.macOS).monoFamily, 'Menlo');
      expect(AppTypography(TargetPlatform.windows).monoFamily, 'Consolas');
      expect(AppTypography(TargetPlatform.linux).monoFamily, 'monospace');
    });

    test('exposes the spec type scale (spec §1)', () {
      final t = AppTypography(TargetPlatform.macOS);
      expect(t.body.fontSize, 13);
      expect(t.caption.fontSize, 11);
      expect(t.headerSemibold.fontSize, 15);
      expect(t.headerSemibold.fontWeight, FontWeight.w600);
      expect(t.mono.fontSize, 12);
      expect(t.mono.fontFamily, 'Menlo');
      expect(t.editorBody.fontSize, 16);
      expect(t.editorBody.height, 1.6);
      expect(t.editorBody.fontFamily, 'Georgia');
    });
  });

  group('AppMetrics', () {
    test('dimension constants match the spec (§2)', () {
      expect(AppMetrics.controlRadius, 8);
      expect(AppMetrics.cardRadius, 10);
      expect(AppMetrics.segmentGap, 8);
      expect(AppMetrics.segmentCardPadding, 16);
      expect(AppMetrics.editorOuterPadding, 48);
      expect(AppMetrics.toolbarHeight, 44);
      expect(AppMetrics.statusBarHeight, 28);
      expect(AppMetrics.railWidth, 320);
      expect(AppMetrics.minWindowWidth, 900);
      expect(AppMetrics.minWindowHeight, 600);
      expect(AppMetrics.defaultWindowWidth, 1100);
      expect(AppMetrics.defaultWindowHeight, 750);
    });
  });

  group('AppTokens.of', () {
    testWidgets('resolves light under a light MaterialApp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: const _Probe(),
        ),
      );
      final tokens = tester.state<_ProbeState>(find.byType(_Probe)).tokens!;
      expect(tokens.colors.isDark, isFalse);
      expect(tokens.colors.bgApp, AppPalette.light.bgApp);
    });

    testWidgets('resolves dark under a dark MaterialApp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const _Probe(),
        ),
      );
      final tokens = tester.state<_ProbeState>(find.byType(_Probe)).tokens!;
      expect(tokens.colors.isDark, isTrue);
      expect(tokens.colors.bgApp, AppPalette.dark.bgApp);
    });

    testWidgets('resolves Cupertino brightness from a CupertinoApp', (
      tester,
    ) async {
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.dark),
          home: const _Probe(),
        ),
      );
      final tokens = tester.state<_ProbeState>(find.byType(_Probe)).tokens!;
      expect(tokens.colors.isDark, isTrue);
      expect(tokens.colors.bgApp, AppPalette.dark.bgApp);
    });
  });

  group('screens render under both themes (token smoke)', () {
    late Directory dir;
    late String configDir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tts_tokens_test_');
      configDir = '${dir.path}/cfg';
      File('$configDir/config.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(const JsonEncoder().convert({}));
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    AppController makeController() =>
        AppController(loader: UserVoiceConfigLoader(configDir: configDir));

    testWidgets('EditorScreen pumps clean under dark Material + Cupertino', (
      tester,
    ) async {
      // The default 800x600 test surface is narrower than the app minimum and
      // the Ahem test font widens text, so remove full-screen layouts; pump on
      // a realistic window instead (see setSpecWindowSize).
      await setSpecWindowSize(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: EditorScreen(controller: makeController()),
        ),
      );
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.dark),
          home: EditorScreen(controller: makeController()),
        ),
      );
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Reset before the framework's invariants check at test end.
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

/// Captures the tokens its [BuildContext] resolved so tests can inspect them.
class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  AppTokens? tokens;

  @override
  Widget build(BuildContext context) {
    tokens = AppTokens.of(context);
    return const SizedBox.shrink();
  }
}
