import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/theme/app_tokens.dart';
import 'package:tts_narrator/src/gui/widgets/segmented_control.dart';

const _items = <(String, String)>[
  ('light', 'Light'),
  ('auto', 'Auto'),
  ('dark', 'Dark'),
];

void main() {
  testWidgets('renders the custom token-driven control', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.light),
        home: Center(
          child: SizedBox(
            width: 300,
            child: SegmentedControl<String>(
              value: 'auto',
              items: _items,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    // Selected label resolves to text-primary, unselected to text-secondary.
    final lightStyle = tester.widget<Text>(find.text('Light')).style!;
    final autoStyle = tester.widget<Text>(find.text('Auto')).style!;
    expect(lightStyle.color, AppPalette.light.textSecondary);
    expect(autoStyle.color, AppPalette.light.textPrimary);
  });

  testWidgets('tapping a segment reports the new value and slides', (
    tester,
  ) async {
    String? changed;
    await tester.pumpWidget(
      CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.light),
        home: Center(
          child: SizedBox(
            width: 300,
            child: SegmentedControl<String>(
              value: 'auto',
              items: _items,
              onChanged: (v) => changed = v,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(changed, 'dark');
  });

  testWidgets('tapping the null-valued segment reports null', (tester) async {
    String? changed = 'unset';
    const items = <(String?, String)>[
      (null, 'Any'),
      ('female', 'Female'),
      ('male', 'Male'),
    ];
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: SegmentedControl<String?>(
              value: 'male',
              items: items,
              onChanged: (v) => changed = v,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Any'));
    await tester.pump();
    expect(changed, isNull);
  });
}