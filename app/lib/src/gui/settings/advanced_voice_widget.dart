import 'package:flutter/material.dart';

import '../controller/app_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_text_field.dart';
import '../widgets/disclosure.dart';

/// The collapsible advanced voice-id entry of the settings rail: a disclosure
/// revealing a free-form raw voice id field that overrides the picked alias.
/// Extracted from the model section so per-model panels can compose it
/// independently of the voice picker.
///
/// The field is owned locally and synced from the controller so a model switch
/// resetting the voice to the new default lands in the field without wiping a
/// user-typed raw id mid-edit.
class AdvancedVoiceWidget extends StatefulWidget {
  const AdvancedVoiceWidget({super.key, required this.controller});

  final AppController controller;

  @override
  State<AdvancedVoiceWidget> createState() => _AdvancedVoiceWidgetState();
}

class _AdvancedVoiceWidgetState extends State<AdvancedVoiceWidget> {
  late final TextEditingController _voiceRaw;

  /// Set while applying controller state into the local field; prevents the
  /// controller notify -> field write -> onChanged -> controller write loop
  /// from echoing.
  bool _syncing = false;

  /// Whether the advanced voice id disclosure is expanded.
  bool _voiceRawExpanded = false;

  AppController get _controller => widget.controller;

  AppTokens get _tokens => AppTokens.of(context);

  @override
  void initState() {
    super.initState();
    _voiceRaw = TextEditingController(text: _controller.voice);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _voiceRaw.dispose();
    super.dispose();
  }

  /// Pushes controller changes back into the local field. The rail is the only
  /// writer to the voice, so this mostly no-ops; the one path it matters on is
  /// a model switch resetting the voice to the new default.
  void _onControllerChanged() {
    setState(() {
      _syncing = true;
      if (_voiceRaw.text != _controller.voice) {
        _voiceRaw.text = _controller.voice;
      }
      _syncing = false;
    });
  }

  void _onVoiceRawChanged(String value) {
    if (_syncing) return;
    _controller.setVoice(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Disclosure(
      key: const Key('voiceAdvancedDisclosure'),
      tooltip: l10n.gui_settings_advancedVoiceIdTooltip,
      label: l10n.gui_settings_advancedVoiceId,
      expanded: _voiceRawExpanded,
      caption: l10n.gui_settings_overridesSelectedAlias,
      onToggle: (value) => setState(() => _voiceRawExpanded = value),
      child: AppTextField(
        key: const Key('voiceRawField'),
        tooltip: l10n.gui_settings_voiceRawFieldTooltip,
        controller: _voiceRaw,
        onChanged: _onVoiceRawChanged,
        hintText: l10n.gui_settings_freeFormVoiceHint,
        style: _tokens.typography.body.copyWith(
          color: _tokens.colors.textPrimary,
        ),
      ),
    );
  }
}
