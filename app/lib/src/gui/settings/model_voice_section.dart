import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../platform/widgets/platform_disclosure.dart';
import '../platform/widgets/platform_dropdown.dart';
import '../platform/widgets/platform_section.dart';
import '../platform/widgets/platform_segmented.dart';
import '../platform/widgets/platform_text_field.dart';
import '../theme/app_text_tokens.dart' show TextTokens, fillTextTemplate;
import '../theme/app_tokens.dart';
import 'settings_labels.dart';

/// The "Model & voice" section of the settings rail: the active model picker,
/// the narrator-gender filter (for gender-tagged voice lists), the voice
/// picker, and the collapsible advanced raw voice-id field.
///
/// Every control writes straight to [AppController], which notifies the editor
/// so the status-bar estimate stays live. The state listens to the controller
/// so a model switch (resetting the voice to the new default) lands in the
/// local fields without losing a user-set raw voice.
class ModelVoiceSection extends StatefulWidget {
  const ModelVoiceSection({super.key, required this.controller});

  final AppController controller;

  @override
  State<ModelVoiceSection> createState() => _ModelVoiceSectionState();
}

class _ModelVoiceSectionState extends State<ModelVoiceSection> {
  late final TextEditingController _voiceRaw;

  /// Set while applying controller state into the local field; prevents the
  /// controller notify -> field write -> onChanged -> controller write loop
  /// from echoing.
  bool _syncing = false;

  /// Whether the advanced voice id disclosure is expanded.
  bool _voiceRawExpanded = false;

  AppController get _controller => widget.controller;

  AppTokens get _tokens => AppTokens.of(context);

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

  List<(String, String)> get _voiceItems => _controller.voiceItems;

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
    return PlatformSection(
      title: TextTokens.gui_settings_modelVoiceSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          settingsFieldLabel(_tokens, TextTokens.gui_settings_modelLabel),
          PlatformDropdown<String>(
            key: const Key('modelDropdown'),
            tooltip: TextTokens.gui_settings_modelDropdownTooltip,
            value: _controller.modelAlias,
            items: _modelItems,
            onChanged: (alias) => _controller.changeModel(alias),
          ),
          settingsFieldLabel(_tokens, TextTokens.gui_settings_voiceAliasLabel),
          if (_controller.hasGenderTags) ...[
            const SizedBox(height: 12),
            PlatformSegmentedControl<VoiceGender>(
              key: const Key('genderControl'),
              tooltip: TextTokens.gui_settings_genderControlTooltip,
              value: _controller.voiceGenderFilter,
              items: const [
                (VoiceGender.neutral, TextTokens.gui_settings_genderAny),
                (VoiceGender.female, TextTokens.gui_settings_genderFemale),
                (VoiceGender.male, TextTokens.gui_settings_genderMale),
              ],
              onChanged: (g) => _controller.voiceGenderFilter = g,
            ),
            const SizedBox(height: 12),
          ],
          PlatformDropdown<String>(
            key: const Key('voiceDropdown'),
            tooltip: TextTokens.gui_settings_voiceDropdownTooltip,
            value: _selectedVoiceLabel,
            items: _voiceItems,
            hint: TextTokens.gui_settings_selectVoiceHint,
            onChanged: (label) => _controller.applyVoiceLabel(label),
          ),
          PlatformDisclosure(
            key: const Key('voiceAdvancedDisclosure'),
            tooltip: TextTokens.gui_settings_advancedVoiceIdTooltip,
            label: TextTokens.gui_settings_advancedVoiceId,
            expanded: _voiceRawExpanded,
            caption: TextTokens.gui_settings_overridesSelectedAlias,
            onToggle: (value) => setState(() => _voiceRawExpanded = value),
            child: PlatformTextField(
              key: const Key('voiceRawField'),
              tooltip: TextTokens.gui_settings_voiceRawFieldTooltip,
              controller: _voiceRaw,
              onChanged: _onVoiceRawChanged,
              hintText: TextTokens.gui_settings_freeFormVoiceHint,
              style: _tokens.typography.body.copyWith(
                color: _tokens.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The voice entry currently selected in the picker. Matches the controller's
  /// friendly label first (an alias pick or a config default), then falls back
  /// to a label equal to the raw voice id so free-form passthrough entries
  /// (e.g. the default voice without an alias) still highlight.
  String? get _selectedVoiceLabel {
    final label = _controller.voiceLabel;
    for (final entry in _voiceItems) {
      if (entry.$1 == label) return entry.$1;
    }
    final voice = _controller.voice;
    for (final entry in _voiceItems) {
      if (entry.$1 == voice) return entry.$1;
    }
    return null;
  }
}
