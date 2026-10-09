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
/// (and macOS vs Material platforms) stay consistent. Screens read the ambient
/// [Brightness] via [AppTokens.of].
///
/// Visual values (colors, type sizes, font weights) live in
/// `app/assets/theme/tokens.json` and are emitted into the private
/// `app_tokens.g.dart` by `tool/generate_tokens.dart`. Run the codegen and
/// commit the regenerated file after editing the JSON; CI re-runs it and
/// fails the build on any drift.
class AppTokens {
  AppTokens(this.brightness)
    : colors = AppPalette.of(brightness),
      typography = AppTypography(
        defaultTargetPlatform,
        colors: AppPalette.of(brightness),
      );

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
  /// Sits between [textPrimary] and [textSecondary]: signals a handle at a
  /// glance without competing with the control's label.
  Color get textTertiary => _gen.textTertiary;

  /// Primary action buttons (`Narrate`), focus rings.
  Color get accentPrimary => _gen.accentPrimary;

  /// Text and icons drawn on accent fills (e.g. `Narrate`, filled buttons).
  ///
  /// White in both modes: the accent palette is saturated enough to hold it.
  /// A token so a future accent change can't strand a hard-coded white.
  Color get textOnAccent => _gen.textOnAccent;

  /// Completed segment icons.
  Color get accentSuccess => _gen.accentSuccess;

  /// Reused / Resumed segment indicators.
  Color get accentWarning => _gen.accentWarning;

  /// Alerts, validation warnings.
  Color get accentError => _gen.accentError;

  /// Muted scrim for subtle drop shadows on floating "surface" elements. Dark
  /// shadows need more ink to stay visible on the near-black surfaces.
  Color get overlayMuted => _gen.overlayMuted;

  /// Material 3 [ColorScheme.fromSeed] seed (theme-independent).
  static const Color m3Seed = _GeneratedPalette.m3Seed;
}

/// Type scale + platform font stacks (spec §1).
///
/// UI sans-serif text omits a family so the platform default system font
/// renders (.SF NS on macOS, Segoe UI on Windows, Ubuntu etc. on Linux). The
/// editor body and the mono readouts are the exception: they pin a concrete
/// family per platform, plus a metric-similar fallback chain, so the macOS and
/// Linux builds render the same shapes instead of drifting to each platform's
/// default.
///
/// Type sizes and weights come from `app/assets/theme/tokens.json`; the
/// platform-resolved family getters below stay in Dart because they depend
/// on [TargetPlatform].
class AppTypography {
  AppTypography(this.platform, {AppPalette? colors})
    : colors = colors ?? AppPalette.of(Brightness.light);

  final TargetPlatform platform;

  /// The palette providing the shared default text colour ([textPrimary]).
  final AppPalette colors;

  static const _GeneratedTypography _t = _GeneratedTypography();

  /// Sans stack for the editor body, pinned on every platform so the two
  /// desktop builds lay out identically. macOS/iOS → Helvetica, Windows →
  /// Arial, Linux → Nimbus Sans — the metric-compatible URW clone of
  /// Helvetica, so glyph advance widths match the macOS build exactly.
  String? get editorSansFamily {
    switch (platform) {
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return 'Helvetica';
      case TargetPlatform.windows:
        return 'Arial';
      default:
        return 'Nimbus Sans';
    }
  }

  /// Metric-similar substitutes for [editorSansFamily], tried in order.
  List<String>? get editorSansFallback {
    switch (platform) {
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return const ['Helvetica Neue', 'Arial', 'sans-serif'];
      case TargetPlatform.windows:
        return const ['Liberation Sans', 'DejaVu Sans', 'sans-serif'];
      default:
        return const ['Liberation Sans', 'DejaVu Sans', 'Noto Sans'];
    }
  }

  /// Monospace stack for metadata/readouts: Menlo (macOS/iOS), Consolas
  /// (Windows), DejaVu Sans Mono (Linux).
  ///
  /// DejaVu Sans Mono is the direct successor of Bitstream Vera Sans Mono — the
  /// face Menlo was derived from — so the readouts keep the same advance widths
  /// on both platforms. The generic `monospace` alias was deliberately avoided
  /// because it resolves to different faces on different distros.
  String? get monoFamily {
    switch (platform) {
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return 'Menlo';
      case TargetPlatform.windows:
        return 'Consolas';
      default:
        return 'DejaVu Sans Mono';
    }
  }

  /// Metric-similar substitutes for [monoFamily], tried in order.
  List<String>? get monoFallback {
    switch (platform) {
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return const ['Courier New', 'monospace'];
      case TargetPlatform.windows:
        return const ['Cascadia Mono', 'Courier New', 'monospace'];
      default:
        return const ['Liberation Mono', 'Noto Sans Mono', 'monospace'];
    }
  }

  /// 13pt UI body (sans) with default colour from the palette.
  TextStyle get body => _t.body;

  /// 14pt settings/dropdown control text (sans) with default colour.
  TextStyle get control => _t.control;

  /// 15pt semibold section / header (sans) with default colour.
  TextStyle get headerSemibold => _t.headerSemibold;

  /// 12pt monospace metadata + readouts with default colour.
  TextStyle get mono => TextStyle(
    fontSize: _t.mono.fontSize,
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    color: colors.textPrimary,
  );

  /// 16pt / 1.6x sans editor body with default colour.
  TextStyle get editorBody => TextStyle(
    fontSize: _t.editorBody.fontSize,
    height: _t.editorBody.height,
    fontFamily: editorSansFamily,
    fontFamilyFallback: editorSansFallback,
    color: colors.textPrimary,
  );
}

/// Grid, shape, and dimension constants (spec §2). Static so they read without
/// a [BuildContext]; gathered here so screens never scatter magic numbers. Not
/// generated from JSON — these are layout-grid constants.
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

  /// Width of a fixed side panel when expanded. Also the width of the settings
  /// screen's model list, which keeps both lists aligned.
  static const double railWidth = 320;

  /// Minimum breathing room around the run view's per-segment action column.
  /// The column itself is content-sized; this is the gap kept between the
  /// segment body and its play/stop action.
  static const double segmentActionWidth = 12;

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

  /// Uniform scale for interactive control circles (slider thumb). Cupertino
  /// native shapes don't expose size parameters, so the whole control is
  /// scaled down slightly for a tighter look.
  static const double controlKnobScale = 0.7;
}
