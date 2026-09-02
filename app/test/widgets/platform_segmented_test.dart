import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/platform/widgets/platform_segmented.dart';
import 'package:tts_narrator/src/gui/theme/app_tokens.dart';

const _items = <(String, String)>[
  ('light', 'Light'),
  ('auto', 'Auto'),
  ('dark', 'Dark'),
];

void main() {
  group('material', () {
    testWidgets('renders a SegmentedButton with the items and selected value', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlatformSegmentedControl<String>(
              value: 'auto',
              items: _items,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      final button = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(button.selected, {'auto'});
      expect(button.segments, hasLength(3));
    });

    testWidgets('tapping a segment reports the new value', (tester) async {
      String? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlatformSegmentedControl<String>(
              value: 'auto',
              items: _items,
              onChanged: (v) => changed = v,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Dark'));
      await tester.pump();
      expect(changed, 'dark');
    });
  });

  group('macOS', () {
    testWidgets('renders the custom token-driven control', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.light),
          home: Center(
            child: SizedBox(
              width: 300,
              child: PlatformSegmentedControl<String>(
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
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('tapping a segment reports the new value and slides', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      String? changed;
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.light),
          home: Center(
            child: SizedBox(
              width: 300,
              child: PlatformSegmentedControl<String>(
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
      debugDefaultTargetPlatformOverride = null;
    });
  });
}