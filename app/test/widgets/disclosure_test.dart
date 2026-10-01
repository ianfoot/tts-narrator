import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/widgets/disclosure.dart';

/// Drives the controlled [Disclosure] the way the real settings sections do:
/// it owns the `expanded` flag and feeds the reported state back in.
class _DisclosureHost extends StatefulWidget {
  const _DisclosureHost({required this.onToggled, this.caption});

  final ValueChanged<bool> onToggled;
  final String? caption;

  @override
  State<_DisclosureHost> createState() => _DisclosureHostState();
}

class _DisclosureHostState extends State<_DisclosureHost> {
  late bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      home: Disclosure(
        key: const Key('disclosure'),
        label: 'Section',
        expanded: _expanded,
        onToggle: (value) {
          setState(() => _expanded = value);
          widget.onToggled(value);
        },
        caption: widget.caption,
        child: const Text('child content'),
      ),
    );
  }
}

void main() {
  Finder headerIcon() => find.descendant(
    of: find.byKey(const Key('disclosure')),
    matching: find.byType(Icon),
  );

  IconData chevron(WidgetTester tester) =>
      tester.widget<Icon>(headerIcon()).icon!;

  Future<void> pumpHost(
    WidgetTester tester, {
    ValueChanged<bool>? onToggled,
    String? caption,
  }) async {
    await tester.pumpWidget(
      _DisclosureHost(onToggled: onToggled ?? (_) {}, caption: caption),
    );
  }

  Future<void> tapHeader(WidgetTester tester) async {
    await tester.tap(find.text('Section'));
    await tester.pump();
  }

  testWidgets('shows a right chevron while collapsed', (tester) async {
    await pumpHost(tester);

    expect(chevron(tester), CupertinoIcons.chevron_right);
    expect(find.text('child content'), findsNothing);
  });

  testWidgets('tracks the expanded prop in both directions', (tester) async {
    await pumpHost(tester);

    await tapHeader(tester);
    expect(chevron(tester), CupertinoIcons.chevron_down);
    expect(find.text('child content'), findsOneWidget);

    await tapHeader(tester);
    expect(chevron(tester), CupertinoIcons.chevron_right);
    expect(find.text('child content'), findsNothing);
  });

  testWidgets('reports the flipped state through onToggle', (tester) async {
    final toggled = <bool>[];
    await pumpHost(tester, onToggled: toggled.add);

    await tapHeader(tester);
    await tapHeader(tester);

    expect(toggled, [true, false]);
  });

  testWidgets('shows the caption only while collapsed', (tester) async {
    await pumpHost(tester, caption: 'A hint about the hidden content');

    expect(find.text('A hint about the hidden content'), findsOneWidget);

    await tapHeader(tester);

    expect(find.text('A hint about the hidden content'), findsNothing);
  });
}