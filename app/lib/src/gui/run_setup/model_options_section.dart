import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_section.dart';
import '../widgets/app_text_field.dart';
import '../widgets/segmented_control.dart';
import 'run_setup_labels.dart';
import 'speed_widget.dart';

/// The "Model options" section: renders the active model's plugin-declared
/// options one per row. Built-in keys (`accent`, `style`, `passagePrefix`,
/// `speed`) bind to the narration settings the controller owns; any other key
/// is ignored — the app interprets the shared convention, never model-specific
/// knowledge. Renders nothing when the active model declares no options.
class ModelOptionsSection extends StatefulWidget {
  const ModelOptionsSection({super.key, required this.controller});

  final AppController controller;

  @override
  State<ModelOptionsSection> createState() => _ModelOptionsSectionState();
}

class _ModelOptionsSectionState extends State<ModelOptionsSection> {
  late final TextEditingController _accent;
  late final TextEditingController _style;
  late final TextEditingController _prefix;

  /// Set while applying controller state into the local fields; prevents the
  /// controller notify -> field write -> onChanged -> controller write loop
  /// from echoing.
  bool _syncing = false;

  /// The model-option keys this app version binds to narration settings.
  static const _bindableModelOptionKeys = {
    'gender',
    'accent',
    'style',
    'passagePrefix',
    'speed',
  };

  AppController get _controller => widget.controller;

  AppTokens get _tokens => AppTokens.of(context);

  @override
  void initState() {
    super.initState();
    _accent = TextEditingController(text: _controller.accent);
    _style = TextEditingController(text: _controller.style);
    _prefix = TextEditingController(text: _controller.passagePrefix);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    for (final c in [_accent, _style, _prefix]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Pushes controller changes back into the local fields. The rail is the
  /// only writer to these values, so this mostly no-ops.
  void _onControllerChanged() {
    setState(() {
      _syncing = true;
      if (_accent.text != _controller.accent) {
        _accent.text = _controller.accent;
      }
      if (_style.text != _controller.style) {
        _style.text = _controller.style;
      }
      if (_prefix.text != _controller.passagePrefix) {
        _prefix.text = _controller.passagePrefix;
      }
      _syncing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spec = _controller.modelUiSpec;
    final options = spec.options
        .where((o) => _bindableModelOptionKeys.contains(o.key))
        .toList();
    if (options.isEmpty) return const SizedBox.shrink();
    return AppSection(
      title: l10n.gui_run_setup_modelOptionsSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options) _buildModelOption(l10n, option),
        ],
      ),
    );
  }

  Widget _buildModelOption(AppLocalizations l10n, ModelUiControl option) {
    switch (option.type) {
      case ModelUiOptionType.bool:
        throw UnsupportedError(
          'bool model options removed (use passagePrefix for [calm])',
        );
      case ModelUiOptionType.gender:
        final g = _controller.voiceGenderFilter;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              runSetupFieldLabel(_tokens, option.label),
              const SizedBox(height: 6),
              SegmentedControl<VoiceGender>(
                key: const Key('genderOptionSegmented'),
                value: g,
                items: [
                  (VoiceGender.neutral, l10n.gui_run_setup_genderAny),
                  (VoiceGender.female, l10n.gui_run_setup_genderFemale),
                  (VoiceGender.male, l10n.gui_run_setup_genderMale),
                ],
                onChanged: (v) => _controller.voiceGenderFilter = v,
              ),
            ],
          ),
        );
      case ModelUiOptionType.text:
      case ModelUiOptionType.multiline:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            runSetupFieldLabel(_tokens, option.label),
            AppTextField(
              key: Key('${option.key}Field'),
              tooltip: switch (option.key) {
                'accent' => l10n.gui_run_setup_accentFieldTooltip,
                'style' => l10n.gui_run_setup_styleFieldTooltip,
                'passagePrefix' => l10n.gui_run_setup_prefixFieldTooltip,
                _ => null,
              },
              controller: _modelOptionController(option.key),
              onChanged: (v) => _setModelOptionText(option.key, v),
              maxLines: option.type == ModelUiOptionType.multiline ? 3 : 1,
              hintText: option.hint,
            ),
          ],
        );
      case ModelUiOptionType.speed:
        return SpeedWidget(controller: _controller);
    }
  }

  TextEditingController _modelOptionController(String key) {
    switch (key) {
      case 'accent':
        return _accent;
      case 'style':
        return _style;
      case 'passagePrefix':
        return _prefix;
    }
    // Unknown text keys are declared by a plugin this app version does not
    // know how to bind; skip them rather than crash the rail.
    throw ArgumentError('No binding for text model option "$key"');
  }

  void _setModelOptionText(String key, String value) {
    if (_syncing) return;
    switch (key) {
      case 'accent':
        _controller.accent = value;
        break;
      case 'style':
        _controller.style = value;
        break;
      case 'passagePrefix':
        _controller.passagePrefix = value;
        break;
    }
  }
}
