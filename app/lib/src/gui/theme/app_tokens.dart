import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

part 'app_tokens.g.dart';

/// The user's appearance choice: follow the system, or force light/dark.
///
/// Kept platform-neutral (an [AppThemeMode], not Flutter's [ThemeMode]) so the
/// controller can own it and the macOS/Material shells map it onto their
/// brightness resolution via [resolveBrightness].
enum AppThemeMode { system, light, dark }

/// Resolves the effective [Brightness] for [mode]: [AppThemeMode.light] and
/// `.dark` pin the value, [AppThemeMode.system] defers to [system].
Brightness resolveBrightness(AppThemeMode mode, Brightness system) {
  switch (mode) {
    case AppThemeMode.light:
      return Brightness.light;
    case AppThemeMode.dark:
      return Brightness.dark;
    case AppThemeMode.system:
      return system;
  }
}

/// Design tokens for the TTS Narrator GUI ("Detailed UI Design Spec").
///
/// Everything visual — colors, typography, spacing/shape metrics — resolves
/// from [AppTokens] instead of inline literals, so the light and dark themes
/// (and macOS vs Material platforms) stay consistent. Screens read the tokens
/// for the ambient [Brightness] via [AppTokens.of].
///
/// Visual values (colors, type sizes, font weights) live in
/// `app/assets/theme/tokens.json` and are emitted into the private
/// `app_tokens.g.dart` by `tool/generate_tokens.dart`. Run the codegen and
/// commit the regenerated file after editing the JSON; CI re-runs it and
/// fails the build on any drift.
class AppTokens {
  AppTokens(this.brightness)
    : colors = AppPalette.of(brightness),
      typography = AppTypography(defaultTargetPlatform);

  /// The ambient brightness the tokens resolve for.
  final Brightness brightness;

  /// The resolved color palette.
  final AppPalette colors;

  /// The resolved platform font stack + type scale.
  final AppTypography typography;

  /// Resolves the tokens for [context]'s ambient brightness.
  ///
  /// Safe under both a [CupertinoApp] and a [MaterialApp]: Material's [Theme]
  /// derives a [CupertinoTheme] for its descendants (brightness mirrored), and
  /// [CupertinoTheme.maybeBrightnessOf] falls back to the platform brightness,
  /// so this never throws for an app-built screen.
  static AppTokens of(BuildContext context) {
    final brightness =
        CupertinoTheme.maybeBrightnessOf(context) ?? Brightness.light;
    return AppTokens(brightness);
  }
}

/// The spec's 10-token color palette (light + dark), plus a few derived
/// tokens ([AppPalette.textOnAccent], [AppPalette.overlayMuted],
/// [AppPalette.m3Seed]).
///
/// Value table (spec §1):
///
/// | token | light | dark |
/// | --- | --- | --- |
/// | `bg-app` | `#FBFBF9` | `#141416` |
/// | `bg-surface` | `#FFFFFF` | `#1E1E22` |
/// | `bg-surface-elevated` | `#F2F2EE` | `#2A2A2E` |
/// | `border-subtle` | `#E5E5E2` | `#2C2C30` |
/// | `text-primary` | `#1C1C1E` | `#EDEDED` |
/// | `text-secondary` | `#6E6E73` | `#8E8E93` |
/// | `text-tertiary` | `#4D4D52` | `#ADADB2` |
/// | `accent-primary` | `#007AFF` | `#0A84FF` |
/// | `accent-success` | `#34C759` | `#30D158` |
/// | `accent-warning` | `#FF9500` | `#FF9F0A` |
/// | `accent-error` | `#FF3B30` | `#FF453A` |
///
/// Color values are authored in `app/assets/theme/tokens.json` and generated
/// into the private `_GeneratedPalette`; this class exposes the public
/// names. The two `const` palette instances keep `AppTokens.of` allocation-
/// free in tests and hot paths.
class AppPalette {
  const AppPalette(this.brightness)
    : _gen = brightness == Brightness.dark
          ? const _GeneratedPalette(isDark: true)
          : const _GeneratedPalette(isDark: false);

  final Brightness brightness;
  final _GeneratedPalette _gen;

  bool get isDark => _gen.isDark;

  static const AppPalette light = AppPalette(Brightness.light);
  static const AppPalette dark = AppPalette(Brightness.dark);

  /// The canonical palette for [brightness].
  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Main window backdrop.
  Color get bgApp => _gen.bgApp;

  /// Cards, drawers, input fields.
  Color get bgSurface => _gen.bgSurface;

  /// Hovers, selected states, summary pills.
  Color get bgSurfaceElevated => _gen.bgSurfaceElevated;

  /// 1px structural dividers and panel borders.
  Color get borderSubtle => _gen.borderSubtle;

  /// Main body text, primary labels.
  Color get textPrimary => _gen.textPrimary;

  /// Metadata, character counts, placeholders.
  Color get textSecondary => _gen.textSecondary;

  /// Interactive control affordances: dropdown chevrons, disclosure arrows.
  ///
  /// Sits between [textPrimary] and [textSecondary]: bright enough to signal
  /// an interactable handle at a glance, but quiet enough that it never
  /// competes with the control's label (which stays [textPrimary]).
  Color get textTertiary => _gen.textTertiary;

  /// Primary action buttons (`Narrate`), focus rings.
  Color get accentPrimary => _gen.accentPrimary;

  /// Text and icons drawn on accent fills (e.g. `Narrate`, filled buttons).
  ///
  /// Pure white in both modes because the accent palette is saturated enough
  /// to hold white at any contrast environment; kept as a token so a future
  /// accent change can't strand a hard-coded white on it.
  Color get textOnAccent => _gen.textOnAccent;

  /// Completed segment icons.
  Color get accentSuccess => _gen.accentSuccess;

  /// Reused / Resumed segment indicators.
  Color get accentWarning => _gen.accentWarning;

  /// Alerts, validation warnings.
  Color get accentError => _gen.accentError;

  /// Muted scrim for subtle drop shadows on floating "surface" elements.
  ///
  /// Light uses a soft 8%-black; dark shadows need a touch more ink to stay
  /// visible on the near-black surfaces.
  Color get overlayMuted => _gen.overlayMuted;

  /// Material 3 [ColorScheme.fromSeed] seed (theme-independent).
  static const Color m3Seed = _GeneratedPalette.m3Seed;
}

/// Type scale + platform font stacks (spec §1).
///
/// UI sans-serif text omits a family so the platform default system font
/// renders (.SF NS on macOS, Segoe UI on Windows, Ubuntu etc. on Linux).
///
/// Type sizes and weights come from `app/assets/theme/tokens.json`; the
/// platform-resolved family getters below stay in Dart because they depend
/// on [TargetPlatform].
class AppTypography {
  AppTypography(this.platform);

  final TargetPlatform platform;

  static const _GeneratedTypography _t = _GeneratedTypography();

  /// Serif stack for the editor body: macOS/iOS → Georgia (New York is not
  /// loadable by Flutter), Windows → Georgia / Times New Roman, Linux →
  /// Nimbus / `serif` fallback.
  String? get editorSerifFamily {
    switch (platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return 'Georgia';
      default:
        return 'serif';
    }
  }

  /// Monospace stack for metadata/readouts: SF Mono / Menlo, Consolas,
  /// Liberation Mono.
  String? get monoFamily {
    switch (platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return 'Menlo';
      case TargetPlatform.windows:
        return 'Consolas';
      default:
        return 'monospace';
    }
  }

  /// 13pt UI body (sans).
  TextStyle get body => _t.body;

  /// 11pt captions (sans).
  TextStyle get caption => _t.caption;

  /// 14pt settings/dropdown control text (sans).
  TextStyle get control => _t.control;

  /// 15pt semibold section / header (sans).
  TextStyle get headerSemibold => _t.headerSemibold;

  /// 12pt monospace metadata + readouts.
  TextStyle get mono =>
      TextStyle(fontSize: _t.mono.fontSize, fontFamily: monoFamily);

  /// 16pt / 1.6x serif editor body.
  TextStyle get editorBody => TextStyle(
    fontSize: _t.editorBody.fontSize,
    height: _t.editorBody.height,
    fontFamily: editorSerifFamily,
  );
}

/// Grid, shape, and dimension constants (spec §2).
///
/// Metrics are static so they read without a [BuildContext]; they are gathered
/// here so screens never scatter magic numbers. Not generated from JSON —
/// these are layout-grid constants that don't change with the brand.
class AppMetrics {
  const AppMetrics._();

  /// Control corner radius (8px).
  static const double controlRadius = 8;

  /// Segment-card corner radius (10px).
  static const double cardRadius = 10;

  /// Vertical gap between segment cards.
  static const double segmentGap = 8;

  /// Padding inside segment cards.
  static const double segmentCardPadding = 16;

  /// Top toolbar height (fixed anchor).
  static const double toolbarHeight = 44;

  /// Bottom status bar height (fixed anchor).
  static const double statusBarHeight = 28;

  /// Settings rail width (fixed when expanded).
  static const double railWidth = 320;

  /// Width of the run view's per-segment action column.
  static const double segmentActionWidth = 100;

  /// Outer left/right padding framing the editor text column.
  static const double editorOuterPadding = 48;

  /// Vertical padding framing the editor text column (top and bottom).
  static const double editorVerticalPadding = 32;

  /// Minimum window size (spec §2).
  static const double minWindowWidth = 900;
  static const double minWindowHeight = 600;

  /// Default window size (spec §2).
  static const double defaultWindowWidth = 1100;
  static const double defaultWindowHeight = 750;
}
