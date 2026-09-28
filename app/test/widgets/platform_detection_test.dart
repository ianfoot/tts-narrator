import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/platform/platform_detection.dart'
    as platform;

void main() {
  group('platform detection', () {
    // Reset override between every test so expectations never leak.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('isMac is true only on macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(platform.isMac, isTrue);
      expect(platform.isLinux, isFalse);
      expect(platform.isWindows, isFalse);
    });

    test('isLinux is true only on Linux', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(platform.isLinux, isTrue);
      expect(platform.isMac, isFalse);
      expect(platform.isWindows, isFalse);
    });

    test('isWindows is true only on Windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(platform.isWindows, isTrue);
      expect(platform.isMac, isFalse);
      expect(platform.isLinux, isFalse);
    });

    test('all getters are false on non-desktop platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(platform.isMac, isFalse);
      expect(platform.isLinux, isFalse);
      expect(platform.isWindows, isFalse);
    });

    test('platformTag maps macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(platform.platformTag, 'macos');
    });

    test('platformTag maps Linux', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(platform.platformTag, 'linux');
    });

    test('platformTag maps Windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(platform.platformTag, 'windows');
    });

    test('platformTag falls back to linux for unknown platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(platform.platformTag, 'linux');
    });
  });
}
