import 'package:flutter/cupertino.dart';

/// Confirms leaving a still-generating narration run.
class ActiveRunConfirmDialog {
  static Future<bool> show({
    required BuildContext context,
  }) async {
    const title = 'Cancel active narration run?';
    const message =
        'Generation stops now; completed clips stay playable in this session.';
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
}