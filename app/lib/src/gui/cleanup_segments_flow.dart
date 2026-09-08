import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'controller/app_controller.dart';
import 'theme/app_text_tokens.dart' show TextTokens, fillTextTemplate;

/// Runs the "Clean Up Segments…" flow: asks for confirmation (deleting the
/// per-segment files forfeits `--resume` reuse — a re-run would re-bill them),
/// then deletes the segments and reports how many were removed, or the error.
///
/// Shared by every surface that exposes the command — the macOS menu bar
/// (which mounts dialogs on the navigator's overlay context) and the editor
/// toolbar (which uses the screen's own context) — so both surfaces present
/// the same confirm and summary dialogs. The dialogs are platform-aware
/// (Cupertino on macOS, Material elsewhere) so the flow stays valid if
/// Linux/Windows later gain a menu surface.
Future<void> runCleanupSegmentsFlow({
  required AppController controller,
  required BuildContext context,
}) async {
  // Capture the intended target: the dialog stays open while the menu bar
  // remains live, so a new run could change the output directory underneath.
  final targetDir = controller.lastRunOutputDir;

  final confirmed = await _confirmDeletion(context);
  if (confirmed != true || !context.mounted) return;

  // Re-validate before deleting: a new run may have started (and even
  // finished) while the dialog was open. If the target directory moved or
  // cleanup is no longer available, bail rather than deleting the new run's
  // segments.
  if (!controller.canCleanupSegments) return;
  if (controller.lastRunOutputDir != targetDir) return;

  try {
    final removed = await controller.cleanupSegments();
    if (!context.mounted) return;
    _showInfoDialog(
      context,
      title: TextTokens.gui_cleanup_deletedTitle,
      message: fillTextTemplate(
        TextTokens.gui_cleanup_removedMessage,
        {
          'removedCount': removed,
          'fileWord': removed == 1
              ? TextTokens.core_plurals_file
              : TextTokens.core_plurals_files,
        },
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    _showInfoDialog(
      context,
      title: TextTokens.gui_cleanup_cleanupFailedTitle,
      message: '$e',
    );
  }
}

bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

/// Platform-aware confirmation dialog; returns true only when the user
/// confirmed deletion.
Future<bool?> _confirmDeletion(BuildContext context) {
  const title = TextTokens.gui_cleanup_confirmTitle;
  const message = TextTokens.gui_cleanup_confirmMessage;
  if (_isMac) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text(title),
        content: const Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(TextTokens.gui_cleanup_cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(TextTokens.gui_cleanup_delete),
          ),
        ],
      ),
    );
  }
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(title),
      content: const Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(TextTokens.gui_cleanup_cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(TextTokens.gui_cleanup_delete),
        ),
      ],
    ),
  );
}

/// Platform-aware dismissible notice (success summary or error).
void _showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  if (_isMac) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(TextTokens.gui_cleanup_ok),
          ),
        ],
      ),
    );
    return;
  }
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text(TextTokens.gui_cleanup_ok),
        ),
      ],
    ),
  );
}
