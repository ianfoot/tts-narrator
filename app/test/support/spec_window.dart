import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/theme/app_tokens.dart';

/// Sizes the test surface to the app's spec default window (see
/// AppMetrics.defaultWindowWidth / defaultWindowHeight) and restores it when
/// the test ends.
///
/// Widget tests default to an 800x600 logical surface. That is narrower than
/// the app's minimum 900x600 window, and the Ahem test font renders every
/// glyph `fontSize` px wide, so full-screen layouts (toolbar + status bar +
/// the 320px panel) overflow at the default size even though they fit at the
/// app's real fonts and window sizes. Screen-level tests therefore pump on a
/// realistic surface through this helper.
///
/// Pass [size] where a test needs a specific surface — a tall one to prove a
/// column scrolls, a narrow one to prove a row truncates. Anything that only
/// needs "not the 800x600 default" should take the spec default instead of
/// inventing a third size.
Future<void> setSpecWindowSize(
  WidgetTester tester, [
  Size? size,
]) async {
  await tester.binding.setSurfaceSize(
    size ?? const Size(AppMetrics.defaultWindowWidth, AppMetrics.defaultWindowHeight),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
