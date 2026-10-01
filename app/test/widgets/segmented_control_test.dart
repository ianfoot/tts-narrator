import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/theme/app_tokens.dart';
import 'package:tts_narrator/src/gui/widgets/segmented_control.dart';

const _items = <(String, String)>[
  ('light', 'Light'),
  ('auto', 'Auto'),
  ('dark', 'Dark'),
];

Widget _host(Widget child) => CupertinoApp(
  theme: const CupertinoThemeData(brightness: Brightness.light),
  home: Center(child: SizedBox(width: 300, child: child)),
);

void main() {
  testWidgets('renders the Cupertino control with token-driven labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SegmentedControl<String>(
          value: 'auto',
          items: _items,
          onChanged: (_) {},
        ),
      ),
    );

    expect(
      find.byType(CupertinoSlidingSegmentedControl<String>),
      findsOneWidget,
    );
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    // Selected label resolves to text-primary, unselected to text-secondary.
    expect(
      tester.widget<Text>(find.text('Light')).style!.color,
      AppPalette.light.textSecondary,
    );
    expect(
      tester.widget<Text>(find.text('Auto')).style!.color,
      AppPalette.light.textPrimary,
    );
  });

  testWidgets('tapping a segment reports the new value', (tester) async {
    String? changed;
    await tester.pumpWidget(
      _host(
        SegmentedControl<String>(
          value: 'auto',
          items: _items,
          onChanged: (v) => changed = v,
        ),
      ),
    );

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(changed, 'dark');
  });

  testWidgets('tapping the selected segment does not re-report the value', (
    tester,
  ) async {
    var changes = 0;
    await tester.pumpWidget(
      _host(
        SegmentedControl<String>(
          value: 'auto',
          items: _items,
          onChanged: (_) => changes++,
        ),
      ),
    );

    await tester.tap(find.text('Auto'));
    await tester.pump();
    expect(changes, 0);
  });

  testWidgets('a null value selects nothing and still reports taps', (
    tester,
  ) async {
    String? changed;
    await tester.pumpWidget(
      _host(
        SegmentedControl<String>(
          value: null,
          items: _items,
          onChanged: (v) => changed = v,
        ),
      ),
    );

    await tester.tap(find.text('Light'));
    await tester.pump();
    expect(changed, 'light');
  });
}