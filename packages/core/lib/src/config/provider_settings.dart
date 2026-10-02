/// Helpers for reading a provider block's settings out of voice config.
///
/// A provider block is an opaque `Map<String, String>` of settings
/// (`base_url`, `api_key`, `api_key_env`, `default_voice`, ...). Nothing here
/// knows what any particular key means — only how to tell whether a block
/// carries a credential, and how to resolve `${ENV_VAR}` secret references
/// before a run starts.
library;

/// Setting names that carry a credential in a provider block.
const List<String> apiKeySettingNames = ['api_key', 'api_key_env'];

/// Whether the provider block [settings] declares a credential.
///
/// The requirement is inferred rather than configured: a block needs a key
/// exactly when it carries `api_key`/`api_key_env`. This is the single source
/// of truth for that inference, shared by the HTTP client (which sends an
/// `Authorization` header only when a key resolves) and the GUI (which shows
/// the API-key section only for keyed providers).
bool providerNeedsApiKey(Map<String, String> settings) =>
    apiKeySettingNames.any((name) => (settings[name] ?? '').isNotEmpty);

/// Matches a `${ENV_NAME}` secret reference in a provider settings value.
final _envRef = RegExp(r'^\$\{(\w+)\}$');

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