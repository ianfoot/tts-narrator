import 'dart:async';

import 'package:tts_narrator_core/tts_narrator_core.dart';

/// Simplest fake speech client: returns the configured bytes and records every
/// call, so narration runs without a real network dependency.
class FakeTtsProvider {
  FakeTtsProvider({List<int>? bytes}) : bytes = bytes ?? 'fake-audio'.codeUnits;

  /// Bytes returned by [synthesize].
  final List<int> bytes;

  final List<
    ({
      String model,
      String? voice,
      String input,
      String responseFormat,
      double? speed,
      String? apiKey,
    })
  >
  calls = [];

  int get callCount => calls.length;

  /// Hand this to `AppController(client: ...)` to drive narration in a test.
  SpeechClient get client => synthesize;

  Future<GeneratedAudio> synthesize({
    required String model,
    required String? voice,
    required String input,
    required String responseFormat,
    required Map<String, String> settings,
    required double? speed,
    String? apiKey,
    AbortToken? abort,
  }) async {
    abort?.throwIfCancelled();
    final currentGate = gate;
    gate = null;
    if (currentGate != null) {
      // Hold the call open so tests can cancel mid-flight; release it later
      // to let the request settle.
      await currentGate.future;
      abort?.throwIfCancelled();
    }
    calls.add((
      model: model,
      voice: voice,
      input: input,
      responseFormat: responseFormat,
      speed: speed,
      apiKey: apiKey,
    ));
    return GeneratedAudio(bytes: bytes);
  }

  /// When non-null, the next [synthesize] awaits it before returning (one-shot:
  /// cleared after the gate consumes it). Lets tests suspend a run mid-flight,
  /// cancel it, start a successor, then release the gate.
  Completer<void>? gate;
}
