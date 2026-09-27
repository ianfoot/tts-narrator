import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../platform/widgets/platform_dropdown.dart';
import '../platform/widgets/platform_section.dart';
import '../theme/app_text_tokens.dart' show TextTokens, fillTextTemplate;
import '../theme/app_tokens.dart';
import 'advanced_voice_widget.dart';
import 'settings_labels.dart';
import 'voice_picker_widget.dart';

/// The "Model & voice" section of the settings rail: the active model picker
/// composing the voice picker and the collapsible advanced raw voice-id field.
///
/// The voice and advanced-voice widgets are extracted so per-model panels can
/// recompose them; every control writes straight to [AppController], which
/// notifies the editor so the status-bar estimate stays live.
///
/// The section listens to the controller so a voice/filter change (e.g. a new
/// gender selection narrowing the voice dropdown) rebuilds the composed
/// children with fresh values.
class ModelVoiceSection extends StatefulWidget {
  const ModelVoiceSection({super.key, required this.controller});

  final AppController controller;

  @override
  State<ModelVoiceSection> createState() => _ModelVoiceSectionState();
}

class _ModelVoiceSectionState extends State<ModelVoiceSection> {
  AppController get _controller => widget.controller;

  AppTokens get _tokens => AppTokens.of(context);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// Rebuilds the composed voice widgets whenever the controller notifies
  /// (e.g. the gender filter narrows the voice dropdown's items/label).
  void _onControllerChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens;
    return PlatformSection(
      title: TextTokens.gui_settings_modelVoiceSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          settingsFieldLabel(tokens, TextTokens.gui_settings_modelLabel),
          PlatformDropdown<String>(
            key: const Key('modelDropdown'),
            tooltip: TextTokens.gui_settings_modelDropdownTooltip,
            value: _controller.modelAlias,
            items: _modelItems,
            onChanged: (alias) => _controller.changeModel(alias),
          ),
          VoicePickerWidget(controller: _controller),
          AdvancedVoiceWidget(controller: _controller),
        ],
      ),
    );
  }

  /// Human-readable model display names, taken from the model's config file
  /// (`display_name`). Unknown/custom aliases without one fall back to the
  /// `alias — id` format.
  List<(String, String)> get _modelItems => [
    for (final p in effectiveModels(_controller.voiceConfig))
      (
        p.alias,
        p.displayName ??
            fillTextTemplate(TextTokens.gui_settings_modelDisplayFallback, {
              'alias': p.alias,
              'id': p.id,
            }),
      ),
  ];
}
