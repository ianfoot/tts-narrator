import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores provider API keys in the OS secure store so the GUI works without a
/// shell environment (double-click launches don't inherit one). Backends:
/// Apple Keychain on macOS, DPAPI / Credential Manager on Windows, libsecret
/// (Secret Service) on Linux.
///
/// Keys are held per provider under [_keyPrefix], so two providers never share
/// a credential and no vendor name is baked into the code.
///
/// The stored key is a fallback in name only — precedence is keychain, config
/// literal, then `${ENV}` reference (see `SettingsController._resolveApiKey`),
/// because the provider file arrives from a remote download and a keychain
/// entry is one this user typed deliberately. The GUI reads keys through the
/// synchronous [_values] cache so run-config building stays synchronous and a
/// model switch needs no reload; [load] is called once at startup, and [save] /
/// [remove] keep the cache current.
class ApiKeyStore extends ChangeNotifier {
  ApiKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Namespace every stored provider key lives under.
  static const _keyPrefix = 'tts-narrator.api_key.';

  /// The secure-storage key holding [provider]'s API key.
  static String _keyFor(String provider) => '$_keyPrefix$provider';

  final FlutterSecureStorage _storage;

  /// Cached keys by provider name. Read synchronously; written only by [load],
  /// [save] and [remove].
  final Map<String, String> _values = {};

  /// The cached key for [provider], or null when none is stored. Synchronous by
  /// design so run-config assembly never awaits platform I/O.
  String? value(String provider) => _values[provider];

  /// Loads every stored provider key into the [value] cache. Safe to call
  /// repeatedly; notifies only when the cached set actually changes.
  ///
  /// Reads the whole namespace once rather than per provider, so switching
  /// models never has to await the platform. Entries outside the prefix are
  /// ignored — the backends return every entry belonging to the app, not just
  /// ours.
  ///
  /// Best-effort: a host without the secure-storage plugin (pure-Dart unit
  /// tests hit this before any binding is initialized), an unreachable
  /// keychain, or any other read failure all mean "no stored key" — the app
  /// still runs from config/env and the missing-key plan error stays the
  /// source of truth.
  Future<void> load() async {
    final Map<String, String> all;
    try {
      all = await _storage.readAll();
    } catch (_) {
      return;
    }
    final next = <String, String>{};
    for (final MapEntry(:key, :value) in all.entries) {
      if (!key.startsWith(_keyPrefix)) continue;
      final provider = key.substring(_keyPrefix.length);
      if (provider.isEmpty) continue;
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) next[provider] = trimmed;
    }
    if (_sameKeys(next)) return;
    _values
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  /// Persists [key] for [provider] and updates the cache. Throws an
  /// [ArgumentError] for an empty/whitespace key — a blank save would only
  /// mask a missing-key plan error later.
  Future<void> save(String provider, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(key, 'key', 'API key must not be empty');
    }
    await _storage.write(key: _keyFor(provider), value: trimmed);
    _values[provider] = trimmed;
    notifyListeners();
  }

  /// Deletes [provider]'s stored key and clears its cached value.
  Future<void> remove(String provider) async {
    await _storage.delete(key: _keyFor(provider));
    _values.remove(provider);
    notifyListeners();
  }

  /// Whether the cached map already holds exactly [other], so a repeated
  /// [load] stays quiet.
  bool _sameKeys(Map<String, String> other) {
    if (other.length != _values.length) return false;
    for (final MapEntry(:key, :value) in other.entries) {
      if (_values[key] != value) return false;
    }
    return true;
  }
}