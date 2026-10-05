import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart'
    show TtsModelProfile, effectiveModels;

import '../../../l10n/app_localizations.dart';
import '../controller/app_controller.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_button.dart';
import 'model_editor.dart';
import 'model_list.dart';

/// Full-screen "Providers & Voices" preferences screen.
///
/// A model list on the left, the selected model's voice table on the right.
/// Everything shown is read from the same config directory the loader uses; the
/// only writes go through [AppController.voiceConfigStore], which puts them in
/// the `user/` overlay so a re-download of the starter configs can never clobber
/// a reader's own voice list.
///
/// The screen is a pushed route rather than a section in the settings rail: the
/// rail is 320px wide, and a voice table with three columns plus per-row
/// actions does not fit in it without becoming unreadable.
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  /// The model whose voices are on show. Independent of the model the narrator
  /// uses — browsing a config must not change what the next run will speak with.
  late String? _selectedAlias;

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _selectedAlias = _initialAlias();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Open on the model the narrator is using, so the screen answers "what am I
  /// about to edit?" without a click; fall back to the first configured model
  /// when nothing is selected, and to null when there are no models at all.
  String? _initialAlias() {
    final models = effectiveModels(_controller.voiceConfig);
    if (models.isEmpty) return null;
    final active = _controller.modelAlias;
    return models.any((m) => m.alias == active) ? active : models.first.alias;
  }

  /// A write landed: re-read the config directory so the table, the override
  /// markers and the voice picker all agree with what is on disk.
  void _onConfigWritten() => _controller.reloadConfig();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final models = effectiveModels(_controller.voiceConfig);
    final store = _controller.voiceConfigStore;
    final selected = _selectedAlias;
    TtsModelProfile? model;
    for (final candidate in models) {
      if (candidate.alias == selected) {
        model = candidate;
        break;
      }
    }
    return CupertinoPageScaffold(
      backgroundColor: tokens.colors.bgApp,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, l10n),
            if (_controller.configWarnings.isNotEmpty)
              _Warnings(warnings: _controller.configWarnings),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: AppMetrics.railWidth,
                    child: ModelList(
                      models: models,
                      selectedAlias: selected,
                      hasOverlay: store.hasOverlayModel,
                      onSelect: (alias) => setState(() => _selectedAlias = alias),
                    ),
                  ),
                  Expanded(
                    child: model == null
                        ? Center(
                            child: Text(
                              l10n.gui_config_noModels,
                              style: tokens.typography.body.copyWith(
                                color: tokens.colors.textSecondary,
                              ),
                            ),
                          )
                        : ModelEditor(
                            model: model,
                            store: store,
                            onChanged: _onConfigWritten,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppLocalizations l10n) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.gui_config_title,
              style: tokens.typography.headerSemibold.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
          ),
          AppButton(
            key: const Key('revealConfigFolderButton'),
            style: AppButtonStyle.outlined,
            tooltip: l10n.gui_config_revealFolderTooltip,
            onPressed: _revealConfigFolder,
            child: Text(
              l10n.gui_config_revealFolder,
              style: tokens.typography.control.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppMetrics.segmentGap),
          AppButton(
            key: const Key('closeConfigButton'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.gui_config_close),
          ),
        ],
      ),
    );
  }

  /// Puts the config directory in front of the user, because every other control
  /// here is an affordance over files that stay on disk. Copying the path as
  /// well means the button is useful on a platform with no "reveal" concept.
  Future<void> _revealConfigFolder() async {
    final dir = _controller.voiceConfigStore.configDir;
    await Clipboard.setData(ClipboardData(text: dir));
    if (Platform.isMacOS) {
      await Process.start('open', [dir]);
    }
  }
}

/// Non-fatal config problems, shown in full rather than truncated: a skipped
/// voice is invisible in the table, so the reason has to live somewhere.
class _Warnings extends StatelessWidget {
  const _Warnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    return Container(
      width: double.infinity,
      color: tokens.colors.bgSurfaceElevated,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.gui_config_warningsTitle,
            style: tokens.typography.body.copyWith(
              color: tokens.colors.accentWarning,
            ),
          ),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                warning,
                style: tokens.typography.mono.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
