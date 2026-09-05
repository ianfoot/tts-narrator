import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/cleanup_segments_flow.dart';

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
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                runCleanupSegmentsFlow(controller: controller, context: context),
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

    testWidgets('bails if a new run starts while the dialog is open', (
      tester,
    ) async {
      final controller = RecordingCleanupController()
        ..cleanupUsable = true
        ..runDir = 'original run dir'
        ..overrideCleanup = () async {
          fail('cleanup ran despite a new run starting mid-dialog');
        };
      await pumpFlowHost(tester, controller);

      await tester.tap(find.text('run'));
      await tester.pumpAndSettle();
      expect(find.text('Delete segment files?'), findsOneWidget);

      // A new run supersedes the target while the user is still deciding.
      controller
        ..cleanupUsable = false
        ..runDir = 'new run dir';
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(controller.cleanups, 0);
      expect(find.text('Segments deleted'), findsNothing);
    });

    testWidgets('bails if the target directory moves while the dialog is open', (
      tester,
    ) async {
      final controller = RecordingCleanupController()
        ..cleanupUsable = true
        ..runDir = 'original run dir'
        ..overrideCleanup = () async {
          fail('cleanup ran against a stale directory');
        };
      await pumpFlowHost(tester, controller);

      await tester.tap(find.text('run'));
      await tester.pumpAndSettle();
      expect(find.text('Delete segment files?'), findsOneWidget);

      controller.runDir = 'another run dir';
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(controller.cleanups, 0);
    });

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
      expect(find.textContaining("can't read segment manifest"), findsOneWidget);
    });
  });
}