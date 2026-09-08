// Codegen for the TTS Narrator design tokens + text tokens.
//
// Reads `app/assets/theme/tokens.json` (design) and
// `app/assets/text_tokens.json` (user-facing strings) and writes
// `app/lib/src/gui/theme/app_tokens.g.dart` / `app_text_tokens.g.dart`
// with deterministic output so trivial JSON edits produce minimal diffs.
//
// Run with:  dart run tool/generate_tokens.dart
//
// The generated files are committed; CI re-runs this script and asserts
// the result is byte-identical (see test/theme/codegen_test.dart).

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final packageRoot = _packageRoot();
  _generateDesignTokens(packageRoot);
  _generateTextTokens(packageRoot);
}

/// Reads `app/assets/theme/tokens.json` and writes
/// `app/lib/src/gui/theme/app_tokens.g.dart`.
void _generateDesignTokens(String packageRoot) {
  final jsonPath = '$packageRoot/assets/theme/tokens.json';
  final outPath = '$packageRoot/lib/src/gui/theme/app_tokens.g.dart';

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

/// Reads `app/assets/text_tokens.json` (all user-facing text strings) and
/// writes `app/lib/src/gui/theme/app_text_tokens.g.dart`: a public
/// [TextTokens] class with one `static const` per leaf, named by joining the
/// token's JSON path with `_` (e.g. `cli.output.modelLine` →
/// `TextTokens.cli_output_modelLine`).
void _generateTextTokens(String packageRoot) {
  final jsonPath = '$packageRoot/assets/text_tokens.json';
  final outPath = '$packageRoot/lib/src/gui/theme/app_text_tokens.g.dart';

  final jsonFile = File(jsonPath);
  if (!jsonFile.existsSync()) {
    stderr.writeln('Missing $jsonPath');
    exit(1);
  }

  final dynamic raw = jsonDecode(jsonFile.readAsStringSync());
  if (raw is! Map<String, dynamic>) {
    stderr.writeln('text_tokens.json must be a JSON object at the top level.');
    exit(1);
  }

  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(renderTextTokens(raw));
  stdout.writeln('Wrote $outPath');
}

/// Renders `app_text_tokens.g.dart` from the parsed [json] text-token tree.
///
/// Each leaf value (strings, and bare ints like `defaults.minWords`) becomes a
/// `static const` on the public `TextTokens` class. String literals are
/// escaped for Dart: backslashes, quotes, and newlines/tabs are escaped
/// normally, and `$` is emitted as `\u0024` so `${...}` / `$name` template
/// placeholders survive compilation verbatim (interpolation happens when the
/// caller formats the token at runtime).
String renderTextTokens(Map<String, dynamic> json) {
  final b = StringBuffer();
  b.writeln('// GENERATED CODE — do not edit by hand.');
  b.writeln('// Source: app/assets/text_tokens.json');
  b.writeln('// Regenerate with: dart run tool/generate_tokens.dart');
  b.writeln();
  b.writeln('part of \'app_text_tokens.dart\';');
  b.writeln();
  b.writeln('/// All user-facing text strings, one `static const` per leaf of');
  b.writeln('/// `app/assets/text_tokens.json`, keyed by its JSON path with');
  b.writeln('/// `_` separators (e.g. `gui.menu.narrate` →');
  b.writeln('/// `TextTokens.gui_menu_narrate`).');
  b.writeln('final class TextTokens {');
  b.writeln('  TextTokens._();');
  for (final (key, value) in _flatten(json, '')) {
    if (value is String) {
      b.writeln("  static const String $key = '${_escapeDart(value)}';");
    } else if (value is int) {
      b.writeln('  static const int $key = $value;');
    } else {
      throw FormatException(
        'text_tokens.json leaf "$key" must be a string or an int.',
      );
    }
  }
  b.writeln('}');
  return b.toString();
}

/// Flattens the nested [json] tree into a list of `(dottedKey, leafValue)`,
/// walking maps in sorted key order so the emitted output is deterministic.
/// A leaf is any non-map value.
List<(String, Object?)> _flatten(Map<String, dynamic> json, String prefix) {
  final out = <(String, Object?)>[];
  for (final key in json.keys.toList()..sort()) {
    final value = json[key];
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      out.addAll(_flatten(value, path));
    } else {
      out.add((path.replaceAll('.', '_'), value));
    }
  }
  return out;
}

/// Escapes [s] for a single-quoted Dart string literal. `$` becomes `\u0024`
/// so `${...}` / `$name` placeholders stay literal in the generated source;
/// backslashes, quotes, and control characters are escaped normally.
String _escapeDart(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    switch (c) {
      case '\\':
        b.write('\\\\');
      case "'":
        b.write("\\'");
      case '\n':
        b.write('\\n');
      case '\r':
        b.write('\\r');
      case '\t':
        b.write('\\t');
      case r'$':
        b.write('\\u0024');
      default:
        b.write(c);
    }
  }
  return b.toString();
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
  TokenSpec({
    required this.colors,
    required this.m3Seed,
    required this.typography,
  });

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
      colors.add(
        ColorEntry.fromJson(entry.key, entry.value as Map<String, dynamic>),
      );
    }

    final m3SeedRaw = json['m3Seed'];
    if (m3SeedRaw is! String) {
      throw const FormatException(
        '`m3Seed` must be a string like "0xFF5E5336".',
      );
    }
    _parseHex(m3SeedRaw, name: 'm3Seed');

    final typoRaw = json['typography'];
    if (typoRaw is! Map<String, dynamic>) {
      throw const FormatException('`typography` must be an object.');
    }
    final typography = <TypeEntry>[];
    for (final entry in typoRaw.entries) {
      typography.add(
        TypeEntry.fromJson(entry.key, entry.value as Map<String, dynamic>),
      );
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

  bool get isPlatformFamily =>
      fontFamily != null && fontFamily!.startsWith('platform:');

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
        throw FormatException(
          'Typography `$name.fontWeight` must look like "w600".',
        );
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
