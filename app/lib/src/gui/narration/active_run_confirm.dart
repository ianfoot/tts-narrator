import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Confirms leaving a still-generating narration run.
class ActiveRunConfirmDialog {
  static Future<bool> show({
    required BuildContext context,
    required bool isMac,
  }) async {
    const title = 'Cancel active narration run?';
    const message =
        'Generation stops now; completed clips stay playable in this session.';
    if (isMac) {
      final result = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text(title),
          content: const Text(message),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancel Run'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Back'),
            ),
          ],
        ),
      );
      return result ?? false;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(title),
        content: const Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel Run'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
