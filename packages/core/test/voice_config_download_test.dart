import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/cli/voice_config_download.dart';

void main() {
  group('downloadVoiceConfigFiles', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tts_download_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('downloads create the directory', () {
      downloadVoiceConfigFiles(dir.path);
      expect(Directory(dir.path).existsSync(), isTrue);
    });
  });
}