import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/platform/platform_detection.dart'
    as platform;

void main() {
  group('platform detection', () {
    // Reset override between every test so expectations never leak.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    for (final (p, own, name) in [
      (TargetPlatform.macOS, 'isMac', 'macos'),
      (TargetPlatform.linux, 'isLinux', 'linux'),
      (TargetPlatform.windows, 'isWindows', 'windows'),
    ]) {
      test('$own is true only on $name', () {
        debugDefaultTargetPlatformOverride = p;
        final flags = {
          'isMac': platform.isMac,
          'isLinux': platform.isLinux,
          'isWindows': platform.isWindows,
        };
        expect(flags[own], isTrue);
        for (final other in flags.keys.where((f) => f != own)) {
          expect(flags[other], isFalse, reason: other);
        }
      });

      test('platformTag maps $name', () {
        debugDefaultTargetPlatformOverride = p;
        expect(platform.platformTag, name);
      });
    }

    test('all getters are false on non-desktop platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(platform.isMac, isFalse);
      expect(platform.isLinux, isFalse);
      expect(platform.isWindows, isFalse);
    });

    test('platformTag falls back to linux for unknown platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(platform.platformTag, 'linux');
    });
  });

  group('acceleratorLabel', () {
    // Reset override between every test so expectations never leak.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('uses Command on macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(platform.acceleratorLabel('N'), '⌘N');
    });

    test('uses Command+Shift on macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(platform.acceleratorLabel('L', shift: true), '⌘⇧L');
    });

    for (final p in [TargetPlatform.linux, TargetPlatform.windows]) {
      test('uses Ctrl on $p', () {
        debugDefaultTargetPlatformOverride = p;
        expect(platform.acceleratorLabel('N'), 'Ctrl+N');
      });
    }

    test('uses Ctrl+Shift on non-macOS platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(platform.acceleratorLabel('L', shift: true), 'Ctrl+Shift+L');
    });
  });
}
