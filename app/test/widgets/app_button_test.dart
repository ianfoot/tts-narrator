import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/theme/app_tokens.dart';
import 'package:tts_narrator/src/gui/widgets/app_button.dart';

/// Default for the optional tap callback; a top-level tear-off is a constant,
/// which an inline `() {}` closure is not.
void _noop() {}

/// Wraps the button the way a caller would, so the tight-slot cases below can
/// reproduce the editor toolbar's bounded height.
typedef Slot = Widget Function(Widget child);

/// Identity slot: an unbounded parent, like the narration screen's column.
Widget _looseSlot(Widget child) => child;

/// The editor toolbar's container is exactly [AppMetrics.toolbarHeight] tall,
/// so the buttons in it only get that much room.
Widget _tightSlot(Widget child) =>
    SizedBox(height: AppMetrics.toolbarHeight, child: child);

void main() {
  const label = Text('Play Full');

  AppButton button({
    AppButtonStyle style = AppButtonStyle.outlined,
    bool compact = true,
    Widget child = label,
    Widget? icon,
    VoidCallback? onPressed = _noop,
  }) => AppButton(
    onPressed: onPressed,
    style: style,
    compact: compact,
    icon: icon,
    child: child,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        home: home,
      ),
    );
  }

  /// Pumps `button(style: style)` inside [slot] and returns the painted label
  /// rect. [AppMetrics.toolbarHeight] matters: the editor toolbar's container
  /// is exactly that tall, so its children only get that much room.
  Future<Rect> labelRectIn(
    WidgetTester tester,
    Slot slot, {
    AppButtonStyle style = AppButtonStyle.outlined,
  }) async {
    await pump(tester, Center(child: slot(button(style: style))));
    return tester.getRect(find.text('Play Full'));
  }

  TextStyle? labelStyle(WidgetTester tester) =>
      tester.renderObject<RenderParagraph>(find.text('Play Full')).text.style;

  AppPalette colorsOf(WidgetTester tester) =>
      AppTokens.of(tester.element(find.byType(AppButton))).colors;

  group('label layout', () {
    testWidgets('outlined keeps the label visible in a tight slot', (
      tester,
    ) async {
      // Regression guard: CupertinoButton's default 16px padding used to eat
      // the toolbar's tight 44px and collapsed this paragraph to zero height,
      // so the icon painted and the text did not. The same button in the
      // narration screen's unbounded column was fine, which made the bug look
      // like a theming problem instead of a layout one.
      final rect = await labelRectIn(tester, _tightSlot);

      expect(rect.height, greaterThan(0));
    });

    testWidgets('filled keeps the label visible in a tight slot', (
      tester,
    ) async {
      final rect = await labelRectIn(
        tester,
        _tightSlot,
        style: AppButtonStyle.filled,
      );

      expect(rect.height, greaterThan(0));
    });

    testWidgets('outlined lays out identically tight and loose', (
      tester,
    ) async {
      // The editor toolbar and the narration screen both render this button;
      // a bounded slot must not change how it looks.
      final tight = await labelRectIn(tester, _tightSlot);
      final tightSize = tester.getSize(find.byType(AppButton));
      final loose = await labelRectIn(tester, _looseSlot);
      final looseSize = tester.getSize(find.byType(AppButton));

      expect(tight.size, loose.size);
      expect(tightSize, looseSize);
    });

    testWidgets('compact trims the horizontal padding', (tester) async {
      await pump(tester, Center(child: button()));
      final compactWidth = tester.getSize(find.byType(AppButton)).width;

      await pump(tester, Center(child: button(compact: false)));
      final fullWidth = tester.getSize(find.byType(AppButton)).width;

      expect(compactWidth, lessThan(fullWidth));
    });
  });

  group('label colour', () {
    testWidgets('outlined pins the label to textPrimary, not the ambient', (
      tester,
    ) async {
      await pump(
        tester,
        DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFFFFFFF)),
          child: Center(child: button()),
        ),
      );

      expect(labelStyle(tester)?.color, colorsOf(tester).textPrimary);
    });

    testWidgets('outlined pins the label to textPrimary in dark mode', (
      tester,
    ) async {
      await pump(tester, Center(child: button()), brightness: Brightness.dark);

      expect(labelStyle(tester)?.color, colorsOf(tester).textPrimary);
    });

    testWidgets('filled pins the label to textOnAccent', (tester) async {
      await pump(tester, Center(child: button(style: AppButtonStyle.filled)));

      expect(labelStyle(tester)?.color, colorsOf(tester).textOnAccent);
    });
  });

  group('icon colour', () {
    testWidgets('filled resolves the icon through its own IconTheme', (
      tester,
    ) async {
      // CupertinoButton's ambient icon colour is accent-primary, i.e. the same
      // colour as the fill behind it, so filled buttons must override it.
      await pump(
        tester,
        Center(
          child: button(
            style: AppButtonStyle.filled,
            icon: const Icon(CupertinoIcons.play_fill),
          ),
        ),
      );

      expect(
        IconTheme.of(tester.element(find.byIcon(CupertinoIcons.play_fill)))
            .color,
        colorsOf(tester).textOnAccent,
      );
    });

    testWidgets('outlined leaves the icon colour to the caller', (
      tester,
    ) async {
      // Outlined icons sit on the surface, so callers pin them to textPrimary;
      // an unpinned icon would inherit accent-primary from the root theme.
      const accentIcon = Icon(
        CupertinoIcons.play_fill,
        color: Color(0xFF1C1C1E),
      );
      await pump(tester, Center(child: button(icon: accentIcon)));

      expect(
        tester.widget<Icon>(find.byIcon(CupertinoIcons.play_fill)).color,
        colorsOf(tester).textPrimary,
      );
    });
  });

  group('interaction', () {
    testWidgets('tapping invokes onPressed', (tester) async {
      var taps = 0;
      await pump(tester, Center(child: button(onPressed: () => taps++)));

      await tester.tap(find.byType(AppButton));

      expect(taps, 1);
    });

    testWidgets('a null onPressed disables the button', (tester) async {
      await pump(tester, Center(child: button(onPressed: null)));

      expect(
        tester.widget<CupertinoButton>(find.byType(CupertinoButton)).onPressed,
        isNull,
      );
    });
  });
}
