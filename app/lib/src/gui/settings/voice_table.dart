import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show TextOverflow, Tooltip;
import 'package:tts_narrator_core/tts_narrator_core.dart'
    show
        EditableVoice,
        VoiceConfigStore,
        VoiceConfigurationError,
        VoiceEdit,
        VoiceGender;

import '../../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/app_icon_button.dart';
import 'settings_labels.dart';
import 'voice_dialog.dart';

/// The voice list for one model: label, provider id, gender, and the default
/// marker, with add / edit / remove when the model is editable.
///
/// A **locked** model (one whose config file omits `voices_editable`) still shows
/// its real voices, just without the controls. That is the point of the flag:
/// Kokoro's and Gemini's lists are what the model actually offers, so editing
/// them would be a lie — but hiding them would be worse, because the reader
/// still needs to know which ids exist to write one into the free-form voice
/// field.
///
/// Every mutation goes through [VoiceConfigStore], which writes the overlay copy
/// rather than the downloaded file, and refuses edits it cannot represent (a
/// blank id, a duplicate id, deleting the default). A refusal is shown inline
/// rather than thrown, because it is the expected answer to a bad edit.
///
/// An unparseable model file is survivable too: hand-editing
/// `user/models/<alias>.json` is the documented way to do this without the app,
/// so a stray comma is a likely way to arrive here. The pane reports the
/// store's message in place of the table instead of throwing out of `build`,
/// which would take the surrounding screen — and its Revert button — down.
class VoiceTable extends StatefulWidget {
  const VoiceTable({
    super.key,
    required this.alias,
    required this.store,
    required this.editable,
    required this.onChanged,
  });

  final String alias;
  final VoiceConfigStore store;

  /// Whether the model's config allows its voice list to be changed here.
  final bool editable;

  /// Called after a write that changed something, so the host can re-read the
  /// config directory and refresh the voice picker.
  final VoidCallback onChanged;

  @override
  State<VoiceTable> createState() => _VoiceTableState();
}

class _VoiceTableState extends State<VoiceTable> {
  /// Last rejection message from the store, replaced on the next attempt.
  String? _error;

  void _after(VoiceEdit edit) {
    if (!mounted) return;
    if (edit.ok) {
      setState(() => _error = null);
      widget.onChanged();
    } else {
      setState(() => _error = edit.error);
    }
  }

  /// Applies a change to one row in place, keeping its label and id. Used by
  /// the gender dropdown, which has no dialog to collect a draft from.
  void _retag(EditableVoice voice, VoiceGender? gender) => _after(
    widget.store.saveVoice(
      widget.alias,
      key: voice.key,
      label: voice.label,
      id: voice.id,
      gender: gender,
    ),
  );

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final draft = await showVoiceDialog(
      context,
      title: l10n.gui_settings_voiceDialogAddTitle,
    );
    if (draft == null) return;
    _after(
      widget.store.saveVoice(
        widget.alias,
        label: draft.label,
        id: draft.id,
        gender: draft.gender,
      ),
    );
  }

  Future<void> _edit(EditableVoice voice) async {
    final l10n = AppLocalizations.of(context);
    final draft = await showVoiceDialog(
      context,
      title: l10n.gui_settings_voiceDialogEditTitle,
      initialLabel: voice.label,
      initialId: voice.id,
      initialGender: voice.gender,
    );
    if (draft == null) return;
    _after(
      widget.store.saveVoice(
        widget.alias,
        key: voice.key,
        label: draft.label,
        id: draft.id,
        gender: draft.gender,
      ),
    );
  }

  /// The table's data, or the reason it cannot be read.
  ///
  /// A read failure is carried as data rather than thrown, so the pane can show
  /// the store's message and keep the screen — and its Revert button — alive.
  ({List<EditableVoice> voices, String? defaultKey, String? failure}) _read() {
    try {
      return (
        voices: widget.store.voicesFor(widget.alias),
        defaultKey: widget.store.defaultVoiceKey(widget.alias),
        failure: null,
      );
    } on VoiceConfigurationError catch (e) {
      return (voices: const [], defaultKey: null, failure: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final read = _read();
    if (read.failure != null) {
      return _Unreadable(
        alias: widget.alias,
        message: read.failure!,
        hasOverlay: widget.store.hasOverlayModel(widget.alias),
      );
    }
    final voices = read.voices;
    final defaultKey = read.defaultKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HeaderRow(),
        for (final voice in voices)
          _VoiceRow(
            voice: voice,
            isDefault: voice.key == defaultKey,
            editable: widget.editable,
            onEdit: () => _edit(voice),
            onRetag: (gender) => _retag(voice, gender),
            onRemove: () =>
                _after(widget.store.removeVoice(widget.alias, voice.key)),
            onSetDefault: () =>
                _after(widget.store.setDefaultVoice(widget.alias, voice.key)),
          ),
        const SizedBox(height: 12),
        if (widget.editable)
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              key: const Key('addVoiceButton'),
              icon: const Icon(CupertinoIcons.add, size: 14),
              onPressed: _add,
              child: Text(l10n.gui_settings_addVoice),
            ),
          )
        else
          Text(
            l10n.gui_settings_voicesLockedCaption(widget.alias),
            style: tokens.typography.body.copyWith(
              color: tokens.colors.textSecondary,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              key: const Key('voiceTableError'),
              style: tokens.typography.body.copyWith(
                color: tokens.colors.accentError,
              ),
            ),
          ),
      ],
    );
  }
}

/// Stands in for the table when the model file cannot be read.
///
/// The store's own message is shown verbatim because it names the file and the
/// syntax error. The revert hint appears only when there is an overlay to revert
/// and points at the button above, which is a sibling of this pane and so stays
/// on screen.
class _Unreadable extends StatelessWidget {
  const _Unreadable({
    required this.alias,
    required this.message,
    required this.hasOverlay,
  });

  final String alias;
  final String message;
  final bool hasOverlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.gui_settings_voicesUnreadableTitle(alias),
          style: tokens.typography.control.copyWith(
            color: tokens.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          key: const Key('voiceTableError'),
          style: tokens.typography.body.copyWith(
            color: tokens.colors.accentError,
          ),
        ),
        if (hasOverlay) ...[
          const SizedBox(height: 6),
          Text(
            l10n.gui_settings_voicesUnreadableRevert,
            style: tokens.typography.body.copyWith(
              color: tokens.colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Column widths, in one place so the header and the rows cannot disagree.
class _RowMetrics {
  static const double defaultMark = 32;
  static const double gender = 120;

  /// Wide enough for the two row actions side by side. [AppIconButton] wraps a
  /// [CupertinoButton], which floors its hit target at the 44px minimum
  /// interactive dimension regardless of icon size — so two of them need 88, not
  /// the 60 their icons suggest. Sizing the column to the icons overflows.
  static const double actions = 88;
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final style = tokens.typography.body.copyWith(
      color: tokens.colors.textSecondary,
    );
    Widget flexCell(String text) => Expanded(
      child: Text(text, style: style, overflow: TextOverflow.ellipsis),
    );
    Widget fixedCell(double width, String text) => SizedBox(
      width: width,
      child: Text(text, style: style, overflow: TextOverflow.ellipsis),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          fixedCell(_RowMetrics.defaultMark, ''),
          flexCell(l10n.gui_settings_columnLabel),
          const SizedBox(width: AppMetrics.segmentGap),
          flexCell(l10n.gui_settings_columnId),
          const SizedBox(width: AppMetrics.segmentGap),
          fixedCell(_RowMetrics.gender, l10n.gui_settings_columnGender),
          const SizedBox(width: AppMetrics.segmentGap),
          fixedCell(_RowMetrics.actions, ''),
        ],
      ),
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.voice,
    required this.isDefault,
    required this.editable,
    required this.onEdit,
    required this.onRetag,
    required this.onRemove,
    required this.onSetDefault,
  });

  final EditableVoice voice;
  final bool isDefault;
  final bool editable;
  final VoidCallback onEdit;
  final ValueChanged<VoiceGender?> onRetag;
  final VoidCallback onRemove;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final colors = tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: _RowMetrics.defaultMark,
            child: _DefaultMark(
              isDefault: isDefault,
              editable: editable,
              voiceId: voice.id,
              onPressed: onSetDefault,
            ),
          ),
          Expanded(
            child: Text(
              voice.label,
              style: tokens.typography.control,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppMetrics.segmentGap),
          Expanded(
            child: Tooltip(
              message: voice.id,
              child: Text(
                voice.id,
                style: tokens.typography.mono.copyWith(
                  color: colors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: AppMetrics.segmentGap),
          SizedBox(
            width: _RowMetrics.gender,
            child: editable
                ? AppDropdown<VoiceGender?>(
                    key: Key('voiceGender_${voice.id}'),
                    value: voice.gender,
                    hint: l10n.gui_settings_genderAny,
                    items: settingsGenderItems(l10n),
                    onChanged: onRetag,
                  )
                : Text(
                    voice.gender.settingsLabel(l10n),
                    style: tokens.typography.control.copyWith(
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const SizedBox(width: AppMetrics.segmentGap),
          SizedBox(
            width: _RowMetrics.actions,
            child: editable
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppIconButton(
                        key: Key('editVoice_${voice.id}'),
                        icon: const Icon(CupertinoIcons.pencil, size: 14),
                        tooltip: l10n.gui_settings_editVoice,
                        onPressed: onEdit,
                      ),
                      AppIconButton(
                        key: Key('removeVoice_${voice.id}'),
                        icon: const Icon(CupertinoIcons.minus, size: 14),
                        tooltip: l10n.gui_settings_removeVoice,
                        onPressed: onRemove,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// The default-voice marker. Editable models get a button (an unfilled circle
/// invites the click); locked models get a plain accent tick, because the
/// default is still worth showing even when it cannot be changed.
class _DefaultMark extends StatelessWidget {
  const _DefaultMark({
    required this.isDefault,
    required this.editable,
    required this.voiceId,
    required this.onPressed,
  });

  final bool isDefault;
  final bool editable;
  final String voiceId;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final icon = Icon(
      isDefault
          ? CupertinoIcons.check_mark_circled_solid
          : CupertinoIcons.circle,
      size: 16,
      color: isDefault ? tokens.colors.accentPrimary : null,
    );
    if (!editable) {
      if (!isDefault) return const SizedBox.shrink();
      return Tooltip(message: l10n.gui_settings_isDefault, child: icon);
    }
    return AppIconButton(
      key: Key('defaultVoiceMark_$voiceId'),
      icon: icon,
      tooltip: isDefault
          ? l10n.gui_settings_isDefault
          : l10n.gui_settings_setDefault,
      onPressed: isDefault ? null : onPressed,
    );
  }
}
