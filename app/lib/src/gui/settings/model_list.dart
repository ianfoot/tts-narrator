import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:tts_narrator_core/tts_narrator_core.dart' show TtsModelProfile;

import '../../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_section.dart';
import 'settings_labels.dart';

/// Left-hand model list for the providers & voices screen.
///
/// Selection is by **alias**, not display name, because aliases are what the
/// config loader keys everything on and two models may share a display name. A
/// dot marks a model that has a local override in the `user/` folder, which is
/// otherwise invisible — the file lives in a directory the reader never opens.
class ModelList extends StatelessWidget {
  const ModelList({
    super.key,
    required this.models,
    required this.selectedAlias,
    required this.hasOverlay,
    required this.onSelect,
  });

  final List<TtsModelProfile> models;
  final String? selectedAlias;

  /// Whether [TtsModelProfile.alias] has a local override file.
  final bool Function(String alias) hasOverlay;

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSection(
      title: l10n.gui_settings_modelsTitle,
      child: models.isEmpty
          ? Text(
              l10n.gui_settings_noModels,
              style: AppTokens.of(context).typography.body,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final model in models)
                  _ModelRow(
                    label: settingsModelLabel(model, l10n),
                    selected: model.alias == selectedAlias,
                    edited: hasOverlay(model.alias),
                    onTap: () => onSelect(model.alias),
                  ),
              ],
            ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.label,
    required this.selected,
    required this.edited,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool edited;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = tokens.colors;
    final row = CupertinoButton(
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
      pressedOpacity: 0.6,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.control.copyWith(
                color: selected ? colors.accentPrimary : colors.textPrimary,
              ),
            ),
          ),
          if (edited)
            Tooltip(
              message: AppLocalizations.of(context)
                  .gui_settings_editedBadgeTooltip,
              child: Icon(
                CupertinoIcons.circle_fill,
                size: 7,
                color: colors.accentPrimary,
              ),
            ),
        ],
      ),
    );
    if (!selected) return row;
    // Selection is a left bar rather than a filled row so the accent dot keeps
    // reading as "this one has a local override" instead of competing with it.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.accentPrimary, width: 2)),
      ),
      child: row,
    );
  }
}
