import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

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

/// The spec's 10-token color palette (light + dark).
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
/// | `accent-primary` | `#007AFF` | `#0A84FF` |
/// | `accent-success` | `#34C759` | `#30D158` |
/// | `accent-warning` | `#FF9500` | `#FF9F0A` |
/// | `accent-error` | `#FF3B30` | `#FF453A` |
class AppPalette {
  const AppPalette(this.brightness);

  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  static const AppPalette light = AppPalette(Brightness.light);
  static const AppPalette dark = AppPalette(Brightness.dark);

  /// The canonical palette for [brightness].
  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Main window backdrop.
  Color get bgApp => isDark ? const Color(0xFF141416) : const Color(0xFFFBFBF9);

  /// Cards, drawers, input fields.
  Color get bgSurface =>
      isDark ? const Color(0xFF1E1E22) : const Color(0xFFFFFFFF);

  /// Hovers, selected states, summary pills.
  Color get bgSurfaceElevated =>
      isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF2F2EE);

  /// 1px structural dividers and panel borders.
  Color get borderSubtle =>
      isDark ? const Color(0xFF2C2C30) : const Color(0xFFE5E5E2);

  /// Main body text, primary labels.
  Color get textPrimary =>
      isDark ? const Color(0xFFEDEDED) : const Color(0xFF1C1C1E);

  /// Metadata, character counts, placeholders.
  Color get textSecondary =>
      isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);

  /// Primary action buttons (`Narrate`), focus rings.
  Color get accentPrimary =>
      isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);

  /// Text and icons drawn on accent fills (e.g. `Narrate`, filled buttons).
  ///
  /// Pure white in both modes because the accent palette ([accentPrimary],
  /// [accentSuccess], …) is saturated enough to hold white at any contrast
  /// environment; kept as a token so a future accent change can't strand a
  /// hard-coded white on it.
  Color get textOnAccent => const Color(0xFFFFFFFF);

  /// Completed segment icons.
  Color get accentSuccess =>
      isDark ? const Color(0xFF30D158) : const Color(0xFF34C759);

  /// Reused / Resumed segment indicators.
  Color get accentWarning =>
      isDark ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500);

  /// Alerts, validation warnings.
  Color get accentError =>
      isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);

  /// Muted scrim for subtle drop shadows on floating "surface" elements.
  ///
  /// Light uses a soft 8%-black; dark shadows need a touch more ink to stay
  /// visible on the near-black surfaces.
  Color get overlayMuted =>
      isDark ? const Color(0x33000000) : const Color(0x14000000);

  /// Material 3 [ColorScheme.fromSeed] seed (theme-independent).
  static const Color m3Seed = Color(0xFF5E5336);
}

/// Type scale + platform font stacks (spec §1).
///
/// UI sans-serif text omits a family so the platform default system font
/// renders (.SF NS on macOS, Segoe UI on Windows, Ubuntu etc. on Linux).
class AppTypography {
  AppTypography(this.platform);

  final TargetPlatform platform;

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
  TextStyle get body => const TextStyle(fontSize: 13);

  /// 11pt captions (sans).
  TextStyle get caption => const TextStyle(fontSize: 11);

  /// 14pt settings/dropdown control text (sans).
  TextStyle get control => const TextStyle(fontSize: 14);

  /// 15pt semibold section / header (sans).
  TextStyle get headerSemibold =>
      const TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

  /// 12pt monospace metadata + readouts.
  TextStyle get mono => TextStyle(fontSize: 12, fontFamily: monoFamily);

  /// 16pt / 1.6x serif editor body.
  TextStyle get editorBody =>
      TextStyle(fontSize: 16, height: 1.6, fontFamily: editorSerifFamily);
}

/// Grid, shape, and dimension constants (spec §2).
///
/// Metrics are static so they read without a [BuildContext]; they are gathered
/// here so screens never scatter magic numbers.
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

  /// Minimum window size (spec §2).
  static const double minWindowWidth = 900;
  static const double minWindowHeight = 600;

  /// Default window size (spec §2).
  static const double defaultWindowWidth = 1100;
  static const double defaultWindowHeight = 750;
}