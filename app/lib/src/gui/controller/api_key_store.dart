import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the OpenRouter API key in the OS secure store so the GUI works
/// without a shell environment (double-click launches don't inherit one).
/// Backends: Apple Keychain on macOS, DPAPI / Credential Manager on Windows,
/// libsecret (Secret Service) on Linux.
///
/// The stored key is a fallback only — config.json literals and `${ENV}`
/// references resolve first ([resolveProviderSettings in the loader]). The GUI
/// reads the key through the synchronous [value] cache so run-config building
/// stays synchronous; [load] is called once at startup, and [save] / [remove]
/// keep the cache current.
class ApiKeyStore extends ChangeNotifier {
  ApiKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Secure-storage key holding the OpenRouter API key.
  static const _keyName = 'openrouter_api_key';

  final FlutterSecureStorage _storage;

  String? _value;

  /// The cached key, or null when none is stored. Synchronous by design so
  /// run-config assembly never awaits platform I/O.
  String? get value => _value;

  /// Loads the stored key into [value]. Safe to call repeatedly; notifies only
  /// when the cached value actually changes.
  ///
  /// Best-effort: a host without the secure-storage plugin (pure-Dart unit
  /// tests hit this before any binding is initialized), an unreachable
  /// keychain, or any other read failure all mean "no stored key" — the app
  /// still runs from config/env and the missing-key plan error stays the
  /// source of truth.
  Future<void> load() async {
    final String? stored;
    try {
      stored = await _storage.read(key: _keyName);
    } catch (_) {
      return;
    }
    final trimmed = stored?.trim();
    final next = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  /// Persists [key] and updates [value]. Throws an [ArgumentError] for an
  /// empty/whitespace key — a blank save would only mask a missing-key plan
  /// error later.
  Future<void> save(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(key, 'key', 'API key must not be empty');
    }
    await _storage.write(key: _keyName, value: trimmed);
    _value = trimmed;
    notifyListeners();
  }

  /// Deletes the stored key and clears [value].
  Future<void> remove() async {
    await _storage.delete(key: _keyName);
    _value = null;
    notifyListeners();
  }
}
