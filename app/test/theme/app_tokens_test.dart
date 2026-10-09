import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/theme/app_tokens.dart';

/// One row per themed colour.
///
/// [key] names the token for failure messages, [get] reads it off a palette, and
/// [diverges] says whether light and dark are *meant* to differ. That flag has to
/// be stated rather than inferred from the two modes disagreeing, because
/// `textOnAccent` is deliberately pure white in both modes and asserting it
/// diverges would be asserting a bug.
///
/// The values themselves are not restated here: they are generated into
/// `app_tokens.g.dart` from the token JSON, and CI already fails the build if
/// that file drifts. What CI cannot see is *which* tokens are meant to move
/// between modes — that is what this table is for.
final _palette = <({String key, bool diverges, Color Function(AppPalette) get})>[
  (key: 'bg-app', diverges: true, get: (p) => p.bgApp),
  (key: 'bg-surface', diverges: true, get: (p) => p.bgSurface),
  (key: 'bg-surface-elevated', diverges: true, get: (p) => p.bgSurfaceElevated),
  (key: 'border-subtle', diverges: true, get: (p) => p.borderSubtle),
  (key: 'text-primary', diverges: true, get: (p) => p.textPrimary),
  (key: 'text-secondary', diverges: true, get: (p) => p.textSecondary),
  (key: 'text-tertiary', diverges: true, get: (p) => p.textTertiary),
  (key: 'accent-primary', diverges: true, get: (p) => p.accentPrimary),
  (key: 'accent-success', diverges: true, get: (p) => p.accentSuccess),
  (key: 'accent-warning', diverges: true, get: (p) => p.accentWarning),
  (key: 'accent-error', diverges: true, get: (p) => p.accentError),
  (key: 'overlay-muted', diverges: true, get: (p) => p.overlayMuted),
  // Foreground on a filled accent. Every accent in the spec is dark enough in
  // light mode and bright enough in dark mode that one white works for both, so
  // this one is *supposed* to be mode-independent.
  (key: 'text-on-accent', diverges: false, get: (p) => p.textOnAccent),
];

/// Every [AppMetrics] constant with the value the spec gives it.
///
/// Reading each through [get] rather than indexing by name keeps this table a
/// place to *see* the scale, while still failing at compile time if a constant
/// is renamed or its type changes.
final _metrics = <({String key, double value, double Function() get})>[
  (key: 'controlRadius', value: 8, get: () => AppMetrics.controlRadius),
  (key: 'cardRadius', value: 10, get: () => AppMetrics.cardRadius),
  (key: 'segmentGap', value: 8, get: () => AppMetrics.segmentGap),
  (key: 'segmentCardPadding', value: 16, get: () => AppMetrics.segmentCardPadding),
  (key: 'segmentActionWidth', value: 12, get: () => AppMetrics.segmentActionWidth),
  (key: 'toolbarHeight', value: 44, get: () => AppMetrics.toolbarHeight),
  (key: 'statusBarHeight', value: 28, get: () => AppMetrics.statusBarHeight),
  (key: 'railWidth', value: 320, get: () => AppMetrics.railWidth),
  (key: 'editorOuterPadding', value: 48, get: () => AppMetrics.editorOuterPadding),
  (key: 'editorVerticalPadding', value: 32, get: () => AppMetrics.editorVerticalPadding),
  (key: 'minWindowWidth', value: 900, get: () => AppMetrics.minWindowWidth),
  (key: 'minWindowHeight', value: 600, get: () => AppMetrics.minWindowHeight),
  (key: 'defaultWindowWidth', value: 1100, get: () => AppMetrics.defaultWindowWidth),
  (key: 'defaultWindowHeight', value: 750, get: () => AppMetrics.defaultWindowHeight),
  // The one non-integer: the Switch/Slider knob is scaled down, not resized to
  // a whole number of logical pixels.
  (key: 'controlKnobScale', value: 0.7, get: () => AppMetrics.controlKnobScale),
];

void main() {
  group('AppPalette', () {
    test('covers every spec token in both light and dark', () {
      final light = AppPalette.light;
      final dark = AppPalette.dark;
      expect(light.isDark, isFalse);
      expect(dark.isDark, isTrue);
      for (final token in _palette) {
        expect(
          token.get(light) == token.get(dark),
          !token.diverges,
          reason: '${token.key} ${token.diverges ? 'must differ' : 'must match'} across modes',
        );
      }
    });

    

    test('no two tokens resolve to the same colour', () {
      // Catches a getter delegating to the wrong generated token, which the
      // codegen cannot see: it checks JSON against app_tokens.g.dart, not the
      // public getters on top. One collision is the design rather than a slip --
      // textOnAccent is white, and so is the light surface.
      const allowed = {('bg-surface', 'text-on-accent')};
      for (final palette in [AppPalette.light, AppPalette.dark]) {
        final claimed = <Color, String>{};
        for (final token in _palette) {
          final clash = claimed[token.get(palette)];
          expect(
            clash == null || allowed.contains((clash, token.key)),
            isTrue,
            reason: clash == null
                ? '${token.key} resolves to a colour no other token claims'
                : '${token.key} resolves to the same colour as $clash in '
                      '${palette.isDark ? 'dark' : 'light'}',
          );
          claimed.putIfAbsent(token.get(palette), () => token.key);
        }
      }
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
    test('resolves the sans + mono family per platform', () {
      expect(AppTypography(TargetPlatform.macOS).editorSansFamily, 'Helvetica');
      expect(AppTypography(TargetPlatform.windows).editorSansFamily, 'Arial');
      expect(
        AppTypography(TargetPlatform.linux).editorSansFamily,
        'Nimbus Sans',
      );
      expect(
        AppTypography(TargetPlatform.android).editorSansFamily,
        'Nimbus Sans',
      );
      expect(AppTypography(TargetPlatform.macOS).monoFamily, 'Menlo');
      expect(AppTypography(TargetPlatform.windows).monoFamily, 'Consolas');
      expect(
        AppTypography(TargetPlatform.linux).monoFamily,
        'DejaVu Sans Mono',
      );
    });

    test('pairs every family with a metric-similar fallback chain', () {
      final mac = AppTypography(TargetPlatform.macOS);
      final linux = AppTypography(TargetPlatform.linux);

      // Helvetica <-> Nimbus Sans and Menlo <-> DejaVu Sans Mono are both
      // metric-compatible pairs, so the fallback must never silently drop to a
      // proportional or generic face.
      expect(linux.editorSansFallback, contains('Liberation Sans'));
      expect(mac.editorSansFallback, contains('Helvetica Neue'));
      expect(linux.monoFallback, contains('Liberation Mono'));
      expect(linux.monoFallback, contains('monospace'));

      // The generated tokens carry no family, so the getters own it.
      expect(mac.body.fontFamily, isNull);
      expect(mac.editorBody.fontFamilyFallback, isNotEmpty);
      expect(mac.mono.fontFamilyFallback, isNotEmpty);
    });

    });

  group('AppMetrics', () {
    test('dimension constants match the spec (§2)', () {
      for (final metric in _metrics) {
        expect(
          metric.get(),
          metric.value,
          reason: 'AppMetrics.${metric.key}',
        );
      }
    });
  });

  group('AppTokens.of', () {
    // The probe reads whatever brightness its ancestor app publishes, so the
    // only thing varying per case is the wrapping app and the brightness it
    // declares.
    for (final wrapper in <({String name, Brightness brightness, Widget Function(Widget home) app})>[
      (
        name: 'light under a light MaterialApp',
        brightness: Brightness.light,
        app: (home) => MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: home,
        ),
      ),
      (
        name: 'dark under a dark MaterialApp',
        brightness: Brightness.dark,
        app: (home) => MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: home,
        ),
      ),
      (
        name: 'Cupertino brightness from a CupertinoApp',
        brightness: Brightness.dark,
        app: (home) => CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.dark),
          home: home,
        ),
      ),
    ]) {
      testWidgets('resolves ${wrapper.name}', (tester) async {
        await tester.pumpWidget(wrapper.app(const _Probe()));
        final tokens = tester.state<_ProbeState>(find.byType(_Probe)).tokens!;
        expect(tokens.colors.isDark, wrapper.brightness == Brightness.dark);
        expect(
          tokens.colors.bgApp,
          AppPalette.of(wrapper.brightness).bgApp,
        );
      });
    }
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
