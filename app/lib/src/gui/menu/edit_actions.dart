import 'package:flutter/widgets.dart';

/// Platform-neutral handlers for the Edit menu's text commands.
///
/// Each dispatches a text intent on the primary focus context, which is the same
/// path the platform's own shortcuts take — so menu and keyboard edits behave
/// identically, including the Cut→clipboard + delete semantics that
/// `CopySelectionTextIntent.cut` encodes.
///
/// Keeping the dispatch here means porting to another platform only swaps the
/// widget that renders the menu (PlatformMenuBar on macOS; an in-app menu on
/// Linux/Windows) — never what each item does.
abstract final class EditActions {
  /// Routes [intent] to whatever currently owns keyboard focus. EditableText
  /// maps the undo/redo/copy/paste/select-all intents (and the cut variant of
  /// [CopySelectionTextIntent]) through its own `Actions`. With no text field
  /// focused this is a harmless no-op.
  static void dispatch(Intent intent) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return;
    Actions.maybeInvoke<Intent>(context, intent);
  }

  static void undo() => dispatch(UndoTextIntent(SelectionChangedCause.toolbar));

  static void redo() => dispatch(RedoTextIntent(SelectionChangedCause.toolbar));

  static void cut() =>
      dispatch(CopySelectionTextIntent.cut(SelectionChangedCause.toolbar));

  static void copy() => dispatch(CopySelectionTextIntent.copy);

  static void paste() =>
      dispatch(PasteTextIntent(SelectionChangedCause.toolbar));

  static void selectAll() =>
      dispatch(SelectAllTextIntent(SelectionChangedCause.toolbar));
}
