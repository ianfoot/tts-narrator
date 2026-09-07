import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';

/// An [AppController] that substitutes the run/cleanup surface so tests of the
/// cleanup flow (menu bar, toolbar, and the shared flow itself) need no real
/// run or disk fixtures.
///
/// [canCleanupSegments] reports [cleanupUsable], [lastRunOutputDir] reports
/// [runDir], and [cleanupSegments] counts calls instead of deleting files.
class RecordingCleanupController extends AppController {
  RecordingCleanupController() : super(loader: _emptyLoader());

  /// What [canCleanupSegments] should report.
  bool cleanupUsable = false;

  /// What [lastRunOutputDir] should report; simulates a run's output dir.
  String? runDir;

  /// Replacement body for [cleanupSegments]; defaults to a counting stub.
  Future<int> Function() overrideCleanup = () async => 0;

  int _cleanups = 0;

  /// How many times [cleanupSegments] ran.
  int get cleanups => _cleanups;

  @override
  String? get lastRunOutputDir => runDir;

  @override
  bool get canCleanupSegments => cleanupUsable;

  @override
  Future<int> cleanupSegments() async {
    _cleanups++;
    return overrideCleanup();
  }
}

/// A loader pointing at an empty temp config dir (the subclass constructor
/// needs one that exists rather than the user's home config).
VoiceConfigLoader _emptyLoader() {
  final dir = Directory.systemTemp.createTempSync('tts_cleanup_loader_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return VoiceConfigLoader(configDir: dir.path);
}
