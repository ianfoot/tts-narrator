import 'package:flutter/cupertino.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart'
    show TtsModelProfile, VoiceConfigStore, VoiceConfigurationError;

import '../../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_section.dart';
import 'voice_table.dart';

/// Right-hand pane for the providers & voices screen: the selected model's
/// read-only metadata, then its voice table.
///
/// Only voices are editable, and only for a model whose config declares
/// `voices_editable`. Everything else about a model — its id, provider, format,
/// pricing — is shown for reference and comes from the downloaded file, because
/// changing those means re-writing a config the vendor owns.
class ModelEditor extends StatelessWidget {
  const ModelEditor({
    super.key,
    required this.model,
    required this.store,
    required this.onChanged,
  });

  final TtsModelProfile model;

  /// The writer every save goes through, so nothing lands in the downloaded
  /// files.
  final VoiceConfigStore store;

  /// Called after a write changed something, so the host can re-read the config
  /// directory and refresh the model list's override markers.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppMetrics.segmentCardPadding),
      children: [
        _Metadata(model: model),
        const SizedBox(height: AppMetrics.segmentGap),
        VoiceTable(
          // Keyed by alias so switching models in the list discards the
          // previous table's state, its last rejection message included. Without
          // it the same state object is reused across models and fish's error
          // would sit under gemini's table until the next edit replaced it.
          key: ValueKey('voiceTable_${model.alias}'),
          alias: model.alias,
          store: store,
          editable: model.voicesEditable,
          onChanged: onChanged,
        ),
        if (store.hasOverlayModel(model.alias)) ...[
          const SizedBox(height: AppMetrics.segmentGap),
          Align(
            alignment: Alignment.centerLeft,
            child: _RevertButton(
              key: ValueKey('revertButton_${model.alias}'),
              alias: model.alias,
              store: store,
              onChanged: onChanged,
            ),
          ),
        ],
      ],
    );
  }
}

/// The read-only model facts in a two-column grid. Values render in
/// [AppTokens.typography.mono] because they are identifiers a reader may want to
/// match against a config file.
class _Metadata extends StatelessWidget {
  const _Metadata({required this.model});

  final TtsModelProfile model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labelWidth = 120.0;
    return AppSection(
      title: model.displayName ?? model.alias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(
            context,
            labelWidth,
            l10n.gui_config_fieldModelId,
            model.id,
          ),
          _row(
            context,
            labelWidth,
            l10n.gui_config_fieldProvider,
            model.provider,
          ),
          _row(
            context,
            labelWidth,
            l10n.gui_config_fieldFormat,
            model.format,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    double labelWidth,
    String label,
    String value,
  ) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: tokens.typography.body.copyWith(
                color: tokens.colors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: tokens.typography.mono)),
        ],
      ),
    );
  }
}

/// Discards the local override for one model. The downloaded file comes back
/// immediately, because the overlay is the only copy of the user's edits and
/// deleting it is the whole point of the button — so it is labelled as such
/// rather than presented as a generic reset.
///
/// This is also the escape hatch out of a model file that does not parse, which
/// is why it lives outside [VoiceTable] rather than inside it: the pane that
/// fails to read is replaced by a message, not by a lost button. The delete can
/// itself fail — a file the user has open, a read-only volume — so that is
/// reported inline too instead of thrown out of the button's callback. Keyed by
/// alias like [VoiceTable], for the same reason: a delete error belongs to the
/// model it happened on.
class _RevertButton extends StatefulWidget {
  const _RevertButton({
    super.key,
    required this.alias,
    required this.store,
    required this.onChanged,
  });

  final String alias;
  final VoiceConfigStore store;
  final VoidCallback onChanged;

  @override
  State<_RevertButton> createState() => _RevertButtonState();
}

class _RevertButtonState extends State<_RevertButton> {
  String? _error;

  void _revert() {
    try {
      if (!widget.store.revertModel(widget.alias)) return;
      setState(() => _error = null);
      widget.onChanged();
    } on VoiceConfigurationError catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppButton(
          key: const Key('revertModelButton'),
          style: AppButtonStyle.outlined,
          tooltip: l10n.gui_config_revertTooltip,
          onPressed: _revert,
          child: Text(
            l10n.gui_config_revert,
            style: tokens.typography.control.copyWith(
              color: tokens.colors.textPrimary,
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              key: const Key('revertModelError'),
              style: tokens.typography.body.copyWith(
                color: tokens.colors.accentError,
              ),
            ),
          ),
      ],
    );
  }
}
