/// Helpers for reading a provider block's settings out of voice config.
///
/// A provider block is an opaque `Map<String, String>` of settings
/// (`base_url`, `api_key`, `api_key_env`, `default_voice`, ...). Nothing here
/// knows what any particular key means — only how to tell whether a block
/// carries a credential, and how to resolve `${ENV_VAR}` secret references
/// before a run starts.
library;

/// Setting names that carry a credential in a provider block.
///
/// Both spellings of the inline key count: the client reads `api_key` then the
/// `apiKey` alias, so a block declaring only the alias declares a credential.
/// `api_key_env` counts as a *declaration* too — its value is a variable name,
/// but the block is asking for a key either way.
const List<String> apiKeySettingNames = ['api_key', 'apiKey', 'api_key_env'];

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

/// The variable name a `${ENV_NAME}` secret reference names, or null when
/// [value] is not such a reference (a literal, or a bare name such as the
/// `api_key_env` value).
///
/// Shared so a caller reporting *where* a credential came from (the GUI's
/// status line) classifies a value exactly as [resolveSettings] expands it,
/// instead of keeping a second copy of the pattern.
String? envRefName(String value) => _envRef.firstMatch(value)?.group(1);

/// Whether [value] is a `${ENV_NAME}` secret reference rather than a literal.
bool isEnvReference(String value) => _envRef.hasMatch(value);

/// Resolves the credential a provider block yields, or null when it is keyless.
///
/// Precedence, matching the order [OpenAiSpeechClient] reads:
///
/// 1. `api_key` (alias `apiKey`) — a literal, or a value already expanded from
///    a `${ENV}` reference by [resolveSettings].
/// 2. `api_key_env` — whose value is the *name* of an environment variable to
///    read from [env], not the credential itself.
///
/// A block with neither sends no `Authorization` header, which is the norm for
/// a local server. Values are trimmed, and an empty or whitespace-only result
/// counts as missing.
///
/// [env] is required rather than defaulted: this module stays free of `dart:io`
/// so environment access remains the caller's job. The GUI passes the same
/// process environment the client reads, so plan-time validation and the HTTP
/// request can never disagree about whether a key exists.
String? resolveProviderApiKey(
  Map<String, String> settings, {
  required Map<String, String> env,
}) {
  for (final name in const ['api_key', 'apiKey']) {
    final value = settings[name]?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  final envName = settings['api_key_env']?.trim();
  if (envName == null || envName.isEmpty) return null;
  final value = env[envName]?.trim();
  return (value == null || value.isEmpty) ? null : value;
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
