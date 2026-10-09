import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/cleanup_segments_flow.dart';

import 'support/l10n_test_support.dart';
import 'support/recording_cleanup_controller.dart';

/// Mounts a navigator with a trigger button that runs the clean-up flow with
/// its live context, mirroring how both the menu bar and the toolbar hand
/// over a context.
Future<void> pumpFlowHost(
  WidgetTester tester,
  RecordingCleanupController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => runCleanupSegmentsFlow(
              controller: controller,
              context: context,
            ),
            child: const Text('run'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('cleanup segments flow', () {
    testWidgets('confirms then deletes and reports how many were removed', (
      tester,
    ) async {
      final controller = RecordingCleanupController()
        ..cleanupUsable = true
        ..runDir = 'the run dir'
        ..overrideCleanup = () async => 2;
      await pumpFlowHost(tester, controller);

      await tester.tap(find.text('run'));
      await tester.pumpAndSettle();
      expect(find.text('Delete segment files?'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(controller.cleanups, 1);
      expect(find.text('Segments deleted'), findsOneWidget);
      expect(find.textContaining('Removed 2 segment files'), findsOneWidget);
    });

    testWidgets('cancelling the confirm leaves the segments in place', (
      tester,
    ) async {
      final controller = RecordingCleanupController()
        ..cleanupUsable = true
        ..runDir = 'the run dir'
        ..overrideCleanup = () async {
          fail('cleanup ran after Cancel');
        };
      await pumpFlowHost(tester, controller);

      await tester.tap(find.text('run'));
      await tester.pumpAndSettle();
      expect(find.text('Delete segment files?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.cleanups, 0);
      expect(find.text('Segments deleted'), findsNothing);
    });

    // The dialog re-validates its target on confirm; either half of that target
    // moving under the user must abort rather than clean a stale directory.
    for (final (name, mutate) in [
      (
        'a new run starts',
        (RecordingCleanupController c) => c
          ..cleanupUsable = false
          ..runDir = 'new run dir',
      ),
      ('the target directory moves', (RecordingCleanupController c) => c.runDir = 'another run dir'),
    ]) {
      testWidgets('bails if $name while the dialog is open', (tester) async {
        final controller = RecordingCleanupController()
          ..cleanupUsable = true
          ..runDir = 'original run dir'
          ..overrideCleanup = () async {
            fail('cleanup ran despite the target changing mid-dialog');
          };
        await pumpFlowHost(tester, controller);

        await tester.tap(find.text('run'));
        await tester.pumpAndSettle();
        expect(find.text('Delete segment files?'), findsOneWidget);

        mutate(controller);
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(controller.cleanups, 0);
        expect(find.text('Segments deleted'), findsNothing);
      });
    }

    testWidgets('surfaces a cleanup failure instead of crashing', (
      tester,
    ) async {
      final controller = RecordingCleanupController()
        ..cleanupUsable = true
        ..runDir = 'the run dir'
        ..overrideCleanup = () async {
          throw StateError('can\'t read segment manifest');
        };
      await pumpFlowHost(tester, controller);

      await tester.tap(find.text('run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Cleanup failed'), findsOneWidget);
      expect(
        find.textContaining("can't read segment manifest"),
        findsOneWidget,
      );
    });
  });
}
