// Codegen for the TTS Narrator design tokens.
//
// Reads `app/assets/theme/tokens.json` and writes
// `app/lib/src/gui/theme/app_tokens.g.dart` with deterministic output so
// trivial JSON edits produce minimal diffs.
//
// Run with:  dart run tool/generate_tokens.dart
//
// The generated file is committed; CI re-runs this script and asserts
// the result is byte-identical (see .github/workflows/tokens.yml and
// test/theme/codegen_test.dart).

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final packageRoot = _packageRoot();
  final jsonPath = '$packageRoot/assets/theme/tokens.json';
  final outPath =
      '$packageRoot/lib/src/gui/theme/app_tokens.g.dart';

  final jsonFile = File(jsonPath);
  if (!jsonFile.existsSync()) {
    stderr.writeln('Missing $jsonPath');
    exit(1);
  }

  final dynamic raw = jsonDecode(jsonFile.readAsStringSync());
  if (raw is! Map<String, dynamic>) {
    stderr.writeln('tokens.json must be a JSON object at the top level.');
    exit(1);
  }

  final spec = TokenSpec.fromJson(raw);
  final rendered = render(spec);

  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(rendered);
  stdout.writeln('Wrote $outPath');
}

/// The "package root" for the codegen: the directory containing `assets/`
/// and `lib/`. When invoked via `dart run tool/generate_tokens.dart` from
/// the app package, this is the current working directory. We accept an
/// override via `--package-root=...` for flexibility in tests and CI.
String _packageRoot() {
  final override = Platform.environment['TOKENS_PACKAGE_ROOT'];
  if (override != null && override.isNotEmpty) return override;
  // Default: the directory the script is running from.
  return Directory.current.path;
}

/// Parsed and validated token manifest.
class TokenSpec {
  TokenSpec({required this.colors, required this.m3Seed, required this.typography});

  /// Color entries in declaration order (so the generated output is stable).
  final List<ColorEntry> colors;
  final String m3Seed;
  final List<TypeEntry> typography;

  factory TokenSpec.fromJson(Map<String, dynamic> json) {
    final colorsRaw = json['colors'];
    if (colorsRaw is! Map<String, dynamic>) {
      throw const FormatException('`colors` must be an object.');
    }
    final colors = <ColorEntry>[];
    for (final entry in colorsRaw.entries) {
      colors.add(ColorEntry.fromJson(entry.key, entry.value as Map<String, dynamic>));
    }

    final m3SeedRaw = json['m3Seed'];
    if (m3SeedRaw is! String) {
      throw const FormatException('`m3Seed` must be a string like "0xFF5E5336".');
    }
    _parseHex(m3SeedRaw, name: 'm3Seed');

    final typoRaw = json['typography'];
    if (typoRaw is! Map<String, dynamic>) {
      throw const FormatException('`typography` must be an object.');
    }
    final typography = <TypeEntry>[];
    for (final entry in typoRaw.entries) {
      typography.add(TypeEntry.fromJson(entry.key, entry.value as Map<String, dynamic>));
    }

    return TokenSpec(colors: colors, m3Seed: m3SeedRaw, typography: typography);
  }
}

class ColorEntry {
  ColorEntry({required this.name, required this.light, required this.dark});

  /// The getter name on `_GeneratedPalette` / `AppPalette` (camelCase).
  final String name;

  /// Hex strings like `"0xFFFBFBF9"`.
  final String light;
  final String dark;

  factory ColorEntry.fromJson(String name, Map<String, dynamic> json) {
    final light = json['light'];
    final dark = json['dark'];
    if (light is! String || dark is! String) {
      throw FormatException('Color `$name` needs `light` and `dark` strings.');
    }
    _parseHex(light, name: '$name.light');
    _parseHex(dark, name: '$name.dark');
    return ColorEntry(name: name, light: light, dark: dark);
  }
}

class TypeEntry {
  TypeEntry({
    required this.name,
    required this.fontSize,
    this.height,
    this.fontWeight,
    this.fontFamily,
  });

  final String name;
  final int fontSize;
  final double? height;

  /// Either `"wNNN"` (emits `FontWeight.wNNN`) or null.
  final String? fontWeight;

  /// Either starts with `platform:` (emits a `fontFamily: <name>` reference
  /// to the AppTypography getter) or is a literal family name, or null.
  final String? fontFamily;

  bool get isPlatformFamily => fontFamily != null && fontFamily!.startsWith('platform:');

  /// The setter name the codegen uses for the platform-family getter on
  /// `AppTypography` (e.g. `monoFamily` for `platform:mono`).
  String get platformFamilyGetter {
    if (!isPlatformFamily) {
      throw StateError('Type `$name` is not a platform family.');
    }
    return '${fontFamily!.substring('platform:'.length)}Family';
  }

  factory TypeEntry.fromJson(String name, Map<String, dynamic> json) {
    final fontSize = json['fontSize'];
    if (fontSize is! int) {
      throw FormatException('Typography `$name` needs integer `fontSize`.');
    }
    final height = json['height'];
    double? heightD;
    if (height != null) {
      if (height is num) {
        heightD = height.toDouble();
      } else {
        throw FormatException('Typography `$name.height` must be a number.');
      }
    }
    final fontWeight = json['fontWeight'];
    if (fontWeight != null) {
      if (fontWeight is! String || !RegExp(r'^w\d{3}$').hasMatch(fontWeight)) {
        throw FormatException('Typography `$name.fontWeight` must look like "w600".');
      }
    }
    final fontFamily = json['fontFamily'];
    if (fontFamily != null && fontFamily is! String) {
      throw FormatException('Typography `$name.fontFamily` must be a string.');
    }
    return TypeEntry(
      name: name,
      fontSize: fontSize,
      height: heightD,
      fontWeight: fontWeight as String?,
      fontFamily: fontFamily as String?,
    );
  }
}

int _parseHex(String s, {required String name}) {
  if (!RegExp(r'^0x[0-9A-Fa-f]{6,8}$').hasMatch(s)) {
    throw FormatException('`$name` must look like "0xAARRGGBB" (got "$s").');
  }
  return int.parse(s);
}

String render(TokenSpec spec) {
  final b = StringBuffer();
  b.writeln('// GENERATED CODE — do not edit by hand.');
  b.writeln('// Source: app/assets/theme/tokens.json');
  b.writeln('// Regenerate with: dart run tool/generate_tokens.dart');
  b.writeln();
  b.writeln('part of \'app_tokens.dart\';');
  b.writeln();
  _renderPalette(b, spec);
  b.writeln();
  _renderTypography(b, spec);
  return b.toString();
}

void _renderPalette(StringBuffer b, TokenSpec spec) {
  b.writeln('class _GeneratedPalette {');
  b.writeln('  const _GeneratedPalette({required this.isDark});');
  b.writeln();
  b.writeln('  final bool isDark;');
  b.writeln();

  for (final c in spec.colors) {
    if (c.light == c.dark) {
      b.writeln('  Color get ${c.name} => const Color(${c.light});');
    } else {
      b.writeln(
        '  Color get ${c.name} => isDark ? const Color(${c.dark}) : const Color(${c.light});',
      );
    }
  }

  b.writeln();
  b.writeln('  static const Color m3Seed = Color(${spec.m3Seed});');
  b.writeln('}');
}

void _renderTypography(StringBuffer b, TokenSpec spec) {
  b.writeln('class _GeneratedTypography {');
  b.writeln('  const _GeneratedTypography();');
  b.writeln();

  for (final t in spec.typography) {
    b.write('  TextStyle get ${t.name} => ');
    final style = _renderTextStyle(t);
    b.writeln('$style;');
  }
  b.writeln('}');
}

String _renderTextStyle(TypeEntry t) {
  if (t.isPlatformFamily) {
    // Platform-resolved family is injected by AppTypography; the generated
    // file only owns the fontSize (and optional height).
    final parts = <String>[];
    parts.add('fontSize: ${t.fontSize}');
    if (t.height != null) {
      parts.add('height: ${t.height}');
    }
    return 'const TextStyle(${parts.join(', ')})';
  }
  final parts = <String>[];
  parts.add('fontSize: ${t.fontSize}');
  if (t.height != null) {
    parts.add('height: ${t.height}');
  }
  if (t.fontWeight != null) {
    parts.add('fontWeight: FontWeight.${t.fontWeight}');
  }
  if (t.fontFamily != null) {
    parts.add("fontFamily: '${t.fontFamily}'");
  }
  return 'const TextStyle(${parts.join(', ')})';
}
