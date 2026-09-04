/// A callback invoked when an [AbortToken] is cancelled.
typedef CancelCallback = void Function();

/// Cooperative cancellation token for long-running narration.
///
/// Threaded through [TtsProvider.synthesize] and `narrate()` so the GUI's Cancel
/// button can stop a run. The CLI never passes one, so behavior there is
/// unchanged (a null token is a no-op).
class AbortToken {
  AbortToken();

  bool _cancelled = false;
  final List<CancelCallback> _onCancelCallbacks = [];

  bool get cancelled => _cancelled;

  /// Requests cancellation. Idempotent.
  ///
  /// Any callbacks registered via [onCancel] fire once, in registration order,
  /// and are then released (so a provider that aborts its in-flight request on
  /// cancel also unregisters cleanly). A throwing callback is contained: it is
  /// reported and the remaining callbacks still run, so cancellation never
  /// fails partway through.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final callbacks = List<CancelCallback>.of(_onCancelCallbacks);
    _onCancelCallbacks.clear();
    for (final callback in callbacks) {
      try {
        callback();
      } catch (_) {
        // Contain subscriber errors: one bad hook must not prevent the rest
        // from observing the cancellation (or escape into cancelRun's caller).
      }
    }
  }

  /// Registers [callback] to run when this token is cancelled, returning an
  /// unsubscribe function.
  ///
  /// When the token is already cancelled, [callback] runs synchronously here
  /// and the returned function is a no-op (so a late subscription still sees
  /// the cancellation without being held onto).
  CancelCallback onCancel(CancelCallback callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    _onCancelCallbacks.add(callback);
    return () => _onCancelCallbacks.remove(callback);
  }

  /// Throws an [AbortException] if cancellation was requested, so callers can
  /// unwind at the next natural checkpoint.
  void throwIfCancelled() {
    if (_cancelled) throw AbortException();
  }
}

/// Thrown when an [AbortToken] has been cancelled.
class AbortException implements Exception {
  const AbortException();

  @override
  String toString() => 'Narration aborted.';
}
