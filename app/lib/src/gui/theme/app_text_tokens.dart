// Public surface for the TTS Narrator text tokens.
//
// Mirrors the design-token split (app_tokens.dart): the values live in
// `app/assets/text_tokens.json` and are emitted into the private part
// `app_text_tokens.g.dart` by `tool/generate_tokens.dart`. Hand-editing the
// `.g.dart` file will be overwritten on the next regeneration, and CI
// fails any PR that changes the JSON without committing the regenerated
// output.

part 'app_text_tokens.g.dart';

/// Fills `$name` / `${name}` placeholders in [template] from [values].
///
/// Text tokens whose JSON value contains interpolation (`$voice`,
/// `$segments`, `${alias}` …) stay literal in the generated constants — the
/// `$` is escaped so the source compiles as-is. This helper binds those
/// placeholders to runtime values: each `$name` or `${name}` occurrence looks
/// up `values[name]` and substitutes its string form; names with no entry
/// (or with a null value) are left untouched, so a partially-filled template
/// degrades gracefully.
String fillTextTemplate(String template, Map<String, Object?> values) {
  if (template.isEmpty || values.isEmpty) return template;
  final out = StringBuffer();
  var i = 0;
  while (i < template.length) {
    if (template[i] != r'$') {
      out.write(template[i]);
      i++;
      continue;
    }
    final braced = i + 1 < template.length && template[i + 1] == '{';
    final nameStart = braced ? i + 2 : i + 1;
    if (braced) {
      final end = template.indexOf('}', nameStart);
      if (end == -1) {
        out.write(template[i]);
        i++;
        continue;
      }
      final name = template.substring(nameStart, end);
      final value = values[name];
      if (value == null) {
        out.write(template[i]);
        i++;
        continue;
      }
      out.write('$value');
      i = end + 1;
      continue;
    }
    var end = nameStart;
    while (end < template.length && _isIdentifierChar(template[end])) {
      end++;
    }
    if (end == nameStart) {
      out.write(template[i]);
      i++;
      continue;
    }
    final name = template.substring(nameStart, end);
    final value = values[name];
    if (value == null) {
      out.write(template[i]);
      i++;
      continue;
    }
    out.write('$value');
    i = end;
  }
  return out.toString();
}

bool _isIdentifierChar(String c) =>
    (c.codeUnitAt(0) >= 0x41 && c.codeUnitAt(0) <= 0x5A) ||
    (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7A) ||
    (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) ||
    c == '_';
