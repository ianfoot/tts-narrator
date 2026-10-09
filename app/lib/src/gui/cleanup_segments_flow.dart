import 'package:flutter/cupertino.dart';

import 'controller/app_controller.dart';
import '../../l10n/app_localizations.dart';

/// Runs the "Clean Up Segments…" flow: asks for confirmation (deleting the
/// per-segment files forfeits `--resume` reuse — a re-run would re-bill them),
/// then deletes the segments and reports how many were removed, or the error.
///
/// Shared by every surface that exposes the command — the macOS menu bar and
/// the editor toolbar — so both present the same confirm and summary dialogs.
Future<void> runCleanupSegmentsFlow({
  required AppController controller,
  required BuildContext context,
}) async {
  // Capture the intended target: the dialog stays open while the menu bar
  // remains live, so a new run could change the output directory underneath.
  final targetDir = controller.lastRunOutputDir;

  final l10n = AppLocalizations.of(context);
  final confirmed = await _confirmDeletion(context);
  if (confirmed != true || !context.mounted) return;

  // Re-validate before deleting: a new run may have started (and even
  // finished) while the dialog was open. Bail rather than delete the new
  // run's segments.
  if (!controller.canCleanupSegments) return;
  if (controller.lastRunOutputDir != targetDir) return;

  try {
    final removed = await controller.cleanupSegments();
    if (!context.mounted) return;
    _showInfoDialog(
      context,
      title: l10n.gui_cleanup_deletedTitle,
      message: l10n.gui_cleanup_removedMessage(
        removed,
        l10n.core_plurals_file(removed),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    _showInfoDialog(
      context,
      title: l10n.gui_cleanup_cleanupFailedTitle,
      message: '$e',
    );
  }
}

/// Confirmation dialog; returns true only when the user confirmed deletion.
Future<bool?> _confirmDeletion(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final title = l10n.gui_cleanup_confirmTitle;
  final message = l10n.gui_cleanup_confirmMessage;
  return showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.gui_cleanup_cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.gui_cleanup_delete),
        ),
      ],
    ),
  );
}

/// Dismissible notice (success summary or error).
void _showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(AppLocalizations.of(context).gui_cleanup_ok),
        ),
      ],
    ),
  );
}
