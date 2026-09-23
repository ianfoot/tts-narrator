import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../platform/widgets/platform_section.dart';
import '../platform/widgets/platform_segmented.dart';
import '../platform/widgets/platform_text_field.dart';
import '../theme/app_text_tokens.dart' show TextTokens;
import '../theme/app_tokens.dart';
import 'settings_labels.dart';

/// The "Model options" section: renders the active model's plugin-declared
/// options one per row. Built-in keys (`accent`, `style`, `passagePrefix`)
/// bind to the narration settings the controller owns; any other key is
/// ignored — the app interprets the shared convention, never model-specific
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
    final spec = _controller.modelUiSpec;
    final options = spec.options
        .where((o) => _bindableModelOptionKeys.contains(o.key))
        .toList();
    if (options.isEmpty) return const SizedBox.shrink();
    return PlatformSection(
      title: TextTokens.gui_settings_modelOptionsSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final option in options) _buildModelOption(option)],
      ),
    );
  }

  Widget _buildModelOption(ModelUiControl option) {
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
              settingsFieldLabel(_tokens, option.label),
              const SizedBox(height: 6),
              PlatformSegmentedControl<VoiceGender>(
                key: const Key('genderOptionSegmented'),
                value: g,
                items: const [
                  (VoiceGender.neutral, TextTokens.gui_settings_genderAny),
                  (VoiceGender.female, TextTokens.gui_settings_genderFemale),
                  (VoiceGender.male, TextTokens.gui_settings_genderMale),
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
            settingsFieldLabel(_tokens, option.label),
            PlatformTextField(
              key: Key('${option.key}Field'),
              tooltip: switch (option.key) {
                'accent' => TextTokens.gui_settings_accentFieldTooltip,
                'style' => TextTokens.gui_settings_styleFieldTooltip,
                'passagePrefix' => TextTokens.gui_settings_prefixFieldTooltip,
                _ => null,
              },
              controller: _modelOptionController(option.key),
              onChanged: (v) => _setModelOptionText(option.key, v),
              maxLines: option.type == ModelUiOptionType.multiline ? 3 : 1,
              hintText: option.hint,
            ),
          ],
        );
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
