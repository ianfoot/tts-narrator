import 'dart:async';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic audioplayers platform for widget tests: every player is a
/// local [StreamController] the test can emit into (prepared is sent
/// automatically on [setSourceUrl]; completion is driven by the test to verify
/// Play/Stop auto-revert). The real method/event channels never run.
class FakeAudioPlatform extends AudioplayersPlatformInterface {
  final Map<String, StreamController<AudioEvent>> _streams = {};
  final List<StreamController<AudioEvent>> _creationOrder = [];

  /// The stream of the most recently created player (the screens use one).
  StreamController<AudioEvent> get lastStream => _creationOrder.last;

  void emitComplete() {
    lastStream.add(const AudioEvent(eventType: AudioEventType.complete));
  }

  @override
  Future<void> create(String playerId) async {
    final stream = StreamController<AudioEvent>.broadcast();
    _streams[playerId] = stream;
    _creationOrder.add(stream);
  }

  @override
  Future<void> dispose(String playerId) async {
    await _streams.remove(playerId)?.close();
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _streams[playerId]!.stream;

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    _streams[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {}

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> resume(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> seek(String playerId, Duration position) async {}

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}

  @override
  Future<void> setAudioContext(
    String playerId,
    AudioContext audioContext,
  ) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<int?> getDuration(String playerId) async => null;

  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}
}

/// Global (all-players) audio scope fake: makes the per-player `AudioPlayer`
/// constructor's global init resolve without a platform channel.
class FakeGlobalAudioPlatform extends GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}

  @override
  Future<void> setGlobalAudioContext(AudioContext context) async {}

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Future<void> emitGlobalError(String code, String message) async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() =>
      const Stream<GlobalAudioEvent>.empty();
}

/// Swaps the audioplayers platform interfaces for the shared fakes and returns
/// the installed [FakeAudioPlatform] so the test can drive completion events.
/// Tests must register teardown (e.g. `addTearDown` from flutter_test) to
/// restore the originals.
FakeAudioPlatform installFakeAudioPlatform() {
  final original = AudioplayersPlatformInterface.instance;
  final originalGlobal = GlobalAudioplayersPlatformInterface.instance;
  final fake = FakeAudioPlatform();
  AudioplayersPlatformInterface.instance = fake;
  GlobalAudioplayersPlatformInterface.instance = FakeGlobalAudioPlatform();
  addTearDown(() {
    AudioplayersPlatformInterface.instance = original;
    GlobalAudioplayersPlatformInterface.instance = originalGlobal;
  });
  return fake;
}
