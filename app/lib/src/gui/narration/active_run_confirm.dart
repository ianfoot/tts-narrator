import 'package:flutter/cupertino.dart';

import '../../../l10n/app_localizations.dart';

/// Confirms leaving a still-generating narration run.
class ActiveRunConfirmDialog {
  static Future<bool> show({required BuildContext context}) async {
    final l10n = AppLocalizations.of(context);
    final title = l10n.gui_narration_confirmCancelTitle;
    final message = l10n.gui_narration_confirmCancelMessage;
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.gui_narration_cancelRun),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.gui_narration_back),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}