// GENERATED CODE — do not edit by hand.
// Source: app/assets/theme/tokens.json
// Regenerate with: dart run tool/generate_tokens.dart

part of 'app_tokens.dart';

class _GeneratedPalette {
  const _GeneratedPalette({required this.isDark});

  final bool isDark;

  Color get bgApp => isDark ? const Color(0xFF141416) : const Color(0xFFFBFBF9);
  Color get bgSurface => isDark ? const Color(0xFF1E1E22) : const Color(0xFFFFFFFF);
  Color get bgSurfaceElevated => isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF2F2EE);
  Color get borderSubtle => isDark ? const Color(0xFF2C2C30) : const Color(0xFFE5E5E2);
  Color get textPrimary => isDark ? const Color(0xFFEDEDED) : const Color(0xFF1C1C1E);
  Color get textSecondary => isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);
  Color get textTertiary => isDark ? const Color(0xFFADADB2) : const Color(0xFF4D4D52);
  Color get accentPrimary => isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
  Color get accentSuccess => isDark ? const Color(0xFF30D158) : const Color(0xFF34C759);
  Color get accentWarning => isDark ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500);
  Color get accentError => isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
  Color get textOnAccent => const Color(0xFFFFFFFF);
  Color get overlayMuted => isDark ? const Color(0x33000000) : const Color(0x14000000);

  static const Color m3Seed = Color(0xFF5E5336);
}

class _GeneratedTypography {
  const _GeneratedTypography();

  TextStyle get body => const TextStyle(fontSize: 13);
  TextStyle get caption => const TextStyle(fontSize: 11);
  TextStyle get control => const TextStyle(fontSize: 14);
  TextStyle get headerSemibold => const TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  TextStyle get mono => const TextStyle(fontSize: 12);
  TextStyle get editorBody => const TextStyle(fontSize: 16, height: 1.6);
}
