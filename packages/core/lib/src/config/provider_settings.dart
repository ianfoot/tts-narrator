/// Helpers for reading a provider block's settings out of voice config.
///
/// A provider block is an opaque `Map<String, String>` of settings
/// (`base_url`, `api_key`, `default_voice`, ...). Settings are resolved without
/// interpreting them -- how a `${ENV_VAR}` reference is expanded, and whether
/// an unresolvable one is fatal, is what [resolveSettings] decides.
///
/// Only the three keys the clients themselves need are named here: the
/// credential [resolveProviderApiKey] reads (`api_key`) and the two spellings
/// of an endpoint [providerBaseUrl] accepts (`base_url`, `endpoint`). Everything
/// else stays opaque.
library;

/// Matches a `${ENV_NAME}` secret reference in a provider settings value.
final _envRef = RegExp(r'^\$\{(\w+)\}$');

/// The variable name a `${ENV_NAME}` secret reference names, or null when
/// [value] is not such a reference (i.e. it is a literal).
///
/// Shared so a caller reporting *where* a credential came from (the GUI's
/// status line) classifies a value exactly as [resolveProviderApiKey] resolves
/// it, instead of keeping a second copy of the pattern.
String? envRefName(String value) => _envRef.firstMatch(value)?.group(1);

/// Whether [value] is a `${ENV_NAME}` secret reference rather than a literal.
bool isEnvReference(String value) => _envRef.hasMatch(value);

/// Resolves the credential a provider block yields, or null when it has none.
///
/// `api_key` is the only credential setting, and its value is either a literal
/// or a `${ENV}` reference naming a variable to read from [env]. There is no
/// separate "which variable" setting: the two spellings are unified here.
///
/// A `${ENV}` reference the runtime cannot fulfil yields null rather than the
/// reference itself, so an unset variable is indistinguishable from an absent
/// key. Values are trimmed; empty or whitespace-only counts as missing.
///
/// Never throws on an unresolvable reference — a run with no usable key sends no
/// `Authorization` header and lets the server decide whether it needed one.
///
/// [env] is required rather than defaulted: this module stays free of `dart:io`
/// so environment access remains the caller's job, which is what lets tests
/// resolve a credential hermetically.
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
/// `base_url` is a **root**, not a full URL: the client appends `/audio/speech`
/// (see `OpenAiSpeechClient`). `endpoint` is a documented alias for it.
///
/// Shared so the HTTP client and [narrate]'s up-front validation read the same
/// key with the same precedence and cannot drift apart.
String? providerBaseUrl(Map<String, String> settings) {
  final root = settings['base_url'] ?? settings['endpoint'];
  if (root == null || root.trim().isEmpty) return null;
  return root.trim();
}

/// Resolves a provider's raw settings map, applying the generic secret rule.
///
/// A value matching `^\$\{(\w+)\}$` reads that environment variable (from [env],
/// defaulting to an empty map) at resolution time — once when the run config is
/// built, never per segment. Any other value passes through literal (so `api_key`
/// literals and already-resolved values survive untouched).
///
/// Throws a [StateError] naming the variable when the referenced env var is
/// missing or empty (an empty value counts as missing, matching the legacy
/// `resolvedApiKey` behaviour); remaining environment access is the caller's
/// job, so core stays provider-agnostic.
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
