/// Cooperative cancellation token for long-running narration.
///
/// Threaded through [TtsClient.synthesize] and `narrate()` so the GUI's Cancel
/// button can stop a run. The CLI never passes one, so behavior there is
/// unchanged (a null token is a no-op).
class AbortToken {
  AbortToken();

  bool _cancelled = false;

  bool get cancelled => _cancelled;

  /// Requests cancellation. Idempotent.
  void cancel() => _cancelled = true;

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