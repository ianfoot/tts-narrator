/// Reads a provider block's settings out of voice config.
///
/// A provider block is an opaque `Map<String, String>`; only the keys the
/// clients need are named here. Interpretation of `${ENV_VAR}` references is
/// [resolveSettings]' job.
library;

/// Matches a `${ENV_NAME}` secret reference in a provider settings value.
final _envRef = RegExp(r'^\$\{(\w+)\}$');

/// The variable a `${ENV_NAME}` reference names, or null when [value] is a
/// literal.
///
/// Shared with [resolveProviderApiKey] so the GUI status line classifies a value
/// exactly as resolution does.
String? envRefName(String value) => _envRef.firstMatch(value)?.group(1);

/// Whether [value] is a `${ENV_NAME}` secret reference rather than a literal.
bool isEnvReference(String value) => _envRef.hasMatch(value);

/// Resolves the credential a provider block yields, or null when it has none.
///
/// `api_key` is the only credential setting, and its value is either a literal
/// or a `${ENV}` reference naming a variable to read from [env].
///
/// An unfulfillable reference yields null rather than the reference itself, so
/// an unset variable is indistinguishable from an absent key. Values are
/// trimmed; empty or whitespace-only counts as missing. Never throws: a run
/// with no usable key sends no `Authorization` header and lets the server
/// decide whether it needed one.
///
/// [env] is required rather than defaulted so this module stays free of
/// `dart:io` and tests can resolve hermetically.
String? resolveProviderApiKey(
  Map<String, String> settings, {
  required Map<String, String> env,
}) {
  final value = settings['api_key']?.trim();
  if (value == null || value.isEmpty) return null;
  final name = envRefName(value);
  if (name == null) return value;
  final resolved = env[name]?.trim();
  return (resolved == null || resolved.isEmpty) ? null : resolved;
}

/// The speech endpoint root declared by the provider block [settings], or null
/// when the block names none.
///
/// `base_url` is a **root**, not a full URL: the client appends `/audio/speech`.
/// `endpoint` is a documented alias for it. Shared so the HTTP client and
/// [narrate]'s up-front validation cannot drift apart.
String? providerBaseUrl(Map<String, String> settings) {
  final root = settings['base_url'] ?? settings['endpoint'];
  if (root == null || root.trim().isEmpty) return null;
  return root.trim();
}

/// Resolves a provider's raw settings map, applying the generic secret rule.
///
/// A `${ENV_VAR}` value reads that variable from [env] (empty by default) once
/// when the run config is built, never per segment. Any other value passes
/// through literal.
///
/// Throws a [StateError] naming the variable when the reference is missing or
/// empty (empty counts as missing, matching the legacy `resolvedApiKey`).
Map<String, String> resolveSettings(
  Map<String, String> raw, {
  Map<String, String>? env,
}) {
  final envMap = env ?? const <String, String>{};
  final out = <String, String>{};
  for (final MapEntry(:key, :value) in raw.entries) {
    final match = _envRef.firstMatch(value);
    if (match == null) {
      out[key] = value;
      continue;
    }
    final name = match.group(1)!;
    final resolved = envMap[name];
    if (resolved == null || resolved.trim().isEmpty) {
      throw StateError(
        'Missing environment variable "$name" referenced by provider '
        'setting "$key".',
      );
    }
    out[key] = resolved;
  }
  return out;
}
