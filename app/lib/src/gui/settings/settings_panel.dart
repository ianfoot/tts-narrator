import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../platform/widgets/platform_disclosure.dart';
import '../platform/widgets/platform_dropdown.dart';
import '../platform/widgets/platform_section.dart';
import '../platform/widgets/platform_segmented.dart';
import '../platform/widgets/platform_slider.dart';
import '../platform/widgets/platform_switch.dart';
import '../platform/widgets/platform_text_field.dart';
import '../theme/app_tokens.dart';

/// Left-side settings rail beside the editor: model & voice, styling, and run
/// options. Every control writes straight to [AppController], which notifies
/// the editor so the status-bar estimate stays live. The rail is hidden via the
/// editor toolbar's toggle; narration is initiated from the toolbar, not here.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late final TextEditingController _voiceRaw;
  late final TextEditingController _accent;
  late final TextEditingController _style;
  late final TextEditingController _prefix;
  late final TextEditingController _sampleLen;

  /// Set while applying controller state into the local fields; prevents the
  /// controller notify -> field write -> onChanged -> controller write loop
  /// from echoing.
  bool _syncing = false;

  /// Whether the advanced voice id disclosure is expanded.
  bool _voiceRawExpanded = false;

  /// Whether sample mode is on (revealing the inline segment count input).
  bool _sampleOn = false;

  AppController get _controller => widget.controller;

  /// Human-readable model display names, taken from the model's config file
  /// (`display_name`). Unknown/custom aliases without one fall back to the
  /// `alias — id` format.
  List<(String, String)> get _modelItems => [
    for (final p in effectiveModels(_controller.voiceConfig))
      (p.alias, p.displayName ?? '${p.alias} — ${p.id}'),
  ];

  List<(String, String)> get _voiceItems => _controller.voiceItems;

  @override
  void initState() {
    super.initState();
    _voiceRaw = TextEditingController(text: _controller.voice);
    _accent = TextEditingController(text: _controller.accent);
    _style = TextEditingController(text: _controller.style);
    _prefix = TextEditingController(text: _controller.passagePrefix);
    _sampleLen = TextEditingController(
      text: _controller.sampleLen?.toString() ?? '',
    );
    _sampleOn = _controller.sampleLen != null;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    for (final c in [_voiceRaw, _accent, _style, _prefix, _sampleLen]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Pushes controller changes back into the local fields. The rail is the
  /// only writer to these values, so this mostly no-ops; the one path it
  /// matters on is a model switch resetting the voice to the new default.
  void _onControllerChanged() {
    setState(() {
      _syncing = true;
      if (_voiceRaw.text != _controller.voice) {
        _voiceRaw.text = _controller.voice;
      }
      if (_accent.text != _controller.accent) {
        _accent.text = _controller.accent;
      }
      if (_style.text != _controller.style) {
        _style.text = _controller.style;
      }
      if (_prefix.text != _controller.passagePrefix) {
        _prefix.text = _controller.passagePrefix;
      }
      if (_sampleLen.text != (_controller.sampleLen?.toString() ?? '')) {
        _sampleLen.text = _controller.sampleLen?.toString() ?? '';
      }
      _sampleOn = _controller.sampleLen != null;
      _syncing = false;
    });
  }

  void _onVoiceRawChanged(String value) {
    if (_syncing) return;
    _controller.setVoice(value);
  }

  void _onAccentChanged(String value) {
    if (_syncing) return;
    _controller.accent = value;
  }

  void _onStyleChanged(String value) {
    if (_syncing) return;
    _controller.style = value;
  }

  void _onPrefixChanged(String value) {
    if (_syncing) return;
    _controller.passagePrefix = value;
  }

  void _onMinWordsChanged(double value) {
    if (_syncing) return;
    _controller.minWords = value.round();
  }

  void _onSampleLenChanged(String value) {
    if (_syncing) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return; // clearing the field to retype; keep sample mode on
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return;
    _controller.sampleLen = parsed;
  }

  void _onSampleOnChanged(bool value) {
    if (_syncing) return;
    _sampleOn = value;
    if (value && _controller.sampleLen == null) {
      _controller.sampleLen = 1;
    } else if (!value) {
      _controller.sampleLen = null;
    }
  }

  AppTokens get _tokens => AppTokens.of(context);

  /// Tier 2 field title (e.g. "Model", "Voice alias"): 13pt Medium primary,
  /// sitting 4px above its control and 12px below the preceding one.
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4, top: 12),
    child: Text(
      text,
      style: _tokens.typography.body.copyWith(
        fontWeight: FontWeight.w500,
        color: _tokens.colors.textPrimary,
      ),
    ),
  );

  /// Inline control label (e.g. "Sample mode", "Skip completed segments") —
  /// Tier 2: 13pt Medium primary, matching the field titles so toggle labels
  /// (previously 14pt/bold) sit at the same visual weight.
  Widget _controlLabel(String text) => Text(
    text,
    style: _tokens.typography.body.copyWith(
      fontWeight: FontWeight.w500,
      color: _tokens.colors.textPrimary,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('settingsPanel'),
      width: AppMetrics.railWidth,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: _tokens.colors.borderSubtle, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                _buildModelVoiceSection(),
                // Model options are declared by the active model's plugin (the
                // provider package); the app has no per-model UI knowledge.
                if (!_controller.modelUiSpec.isEmpty)
                  _buildModelOptionsSection(_controller.modelUiSpec),
                _buildRunSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Text(
        'Settings',
        style: _tokens.typography.headerSemibold.copyWith(
          color: _tokens.colors.accentPrimary,
        ),
      ),
    );
  }

  Widget _buildModelVoiceSection() {
    return PlatformSection(
      title: 'Model & voice',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Model'),
          PlatformDropdown<String>(
            key: const Key('modelDropdown'),
            value: _controller.modelAlias,
            items: _modelItems,
            onChanged: (alias) => _controller.changeModel(alias),
          ),
          _label('Voice alias'),
          if (_controller.hasGenderTags) ...[
            const SizedBox(height: 12),
            PlatformSegmentedControl<VoiceGender?>(
              key: const Key('genderControl'),
              value: _controller.voiceGenderFilter,
              items: const [
                (null, 'Any'),
                (VoiceGender.female, 'Female'),
                (VoiceGender.male, 'Male'),
              ],
              onChanged: (g) => _controller.voiceGenderFilter = g,
            ),
            const SizedBox(height: 12),
          ],
          PlatformDropdown<String>(
            key: const Key('voiceDropdown'),
            value: _selectedVoiceLabel,
            items: _voiceItems,
            hint: 'Select a Voice...',
            onChanged: (label) => _controller.applyVoiceLabel(label),
          ),
          PlatformDisclosure(
            key: const Key('voiceAdvancedDisclosure'),
            label: 'Advanced Voice ID',
            expanded: _voiceRawExpanded,
            caption: 'Overrides selected alias',
            onToggle: (value) => setState(() => _voiceRawExpanded = value),
            child: PlatformTextField(
              key: const Key('voiceRawField'),
              controller: _voiceRaw,
              onChanged: _onVoiceRawChanged,
              hintText: 'free-form id or provider voice',
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

  /// Renders the active model's plugin-declared options one per row. Built-in
  /// keys (`accent`, `style`, `passagePrefix`, `useCalmTag`) bind to the
  /// narration settings the controller owns; any other key is ignored — the
  /// app interprets the shared convention, never model-specific knowledge.
  Widget _buildModelOptionsSection(ModelUiSpec spec) {
    final options = spec.options
        .where((o) => _bindableModelOptionKeys.contains(o.key))
        .toList();
    if (options.isEmpty) return const SizedBox.shrink();
    return PlatformSection(
      title: 'Model options',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final option in options) _buildModelOption(option)],
      ),
    );
  }

  /// The model-option keys this app version binds to narration settings.
  static const _bindableModelOptionKeys = {
    'gender',
    'accent',
    'style',
    'passagePrefix',
    'useCalmTag',
  };

  Widget _buildModelOption(ModelUiOption option) {
    switch (option.type) {
      case ModelUiOptionType.bool:
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              Expanded(child: _controlLabel(option.label)),
              PlatformSwitch(
                key: Key('${option.key}Switch'),
                value: _modelOptionBool(option.key),
                onChanged: (v) => _setModelOptionBool(option.key, v),
              ),
            ],
          ),
        );
      case ModelUiOptionType.gender:
        final g = _controller.voiceGenderFilter;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label(option.label),
              const SizedBox(height: 6),
              PlatformSegmentedControl<VoiceGender?>(
                key: const Key('genderOptionSegmented'),
                value: g,
                items: const [
                  (null, 'Any'),
                  (VoiceGender.female, 'Female'),
                  (VoiceGender.male, 'Male'),
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
            _label(option.label),
            PlatformTextField(
              key: Key('${option.key}Field'),
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
    switch (key) {
      case 'accent':
        _onAccentChanged(value);
        break;
      case 'style':
        _onStyleChanged(value);
        break;
      case 'passagePrefix':
        _onPrefixChanged(value);
        break;
    }
  }

  bool _modelOptionBool(String key) {
    switch (key) {
      case 'useCalmTag':
        return _controller.useCalmTag;
    }
    throw ArgumentError('No binding for bool model option "$key"');
  }

  void _setModelOptionBool(String key, bool value) {
    if (key == 'useCalmTag') _controller.useCalmTag = value;
  }

  Widget _buildRunSection() {
    return PlatformSection(
      title: 'Run',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_controller.wholeFileAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(child: _controlLabel('Send whole file')),
                  PlatformSwitch(
                    key: const Key('wholeFileSwitch'),
                    value: _controller.sendWholeFile,
                    onChanged: (v) => _controller.sendWholeFile = v,
                  ),
                ],
              ),
            ),
          if (!_controller.sendWholeFile) ...[
            _label('Min words per segment'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PlatformSlider(
                    key: const Key('minWordsSlider'),
                    value: _controller.minWords.toDouble(),
                    onChanged: _onMinWordsChanged,
                    min: 10,
                    max: 100,
                    divisions: 90,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: const Key('minWordsBadge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _tokens.colors.bgSurfaceElevated,
                    borderRadius: BorderRadius.circular(
                      AppMetrics.controlRadius,
                    ),
                  ),
                  child: Text('$minWords', style: _tokens.typography.mono),
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(child: _controlLabel('Sample mode')),
                PlatformSwitch(
                  key: const Key('sampleSwitch'),
                  value: _sampleOn,
                  onChanged: _onSampleOnChanged,
                ),
              ],
            ),
          ),
          if (_sampleOn)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Narrate first segments only',
                      style: _tokens.typography.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: _tokens.colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: PlatformTextField(
                      key: const Key('sampleLenField'),
                      controller: _sampleLen,
                      onChanged: _onSampleLenChanged,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: _controlLabel('Skip completed segments (Resume)'),
                ),
                PlatformSwitch(
                  key: const Key('resumeSwitch'),
                  value: _controller.resume,
                  onChanged: (v) => _controller.resume = v,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int get minWords => _controller.minWords;
}
