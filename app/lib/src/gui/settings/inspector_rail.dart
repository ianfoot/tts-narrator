import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../platform/widgets/platform_button.dart';
import '../platform/widgets/platform_dropdown.dart';
import '../platform/widgets/platform_icon_button.dart';
import '../platform/widgets/platform_section.dart';
import '../platform/widgets/platform_switch.dart';
import '../platform/widgets/platform_text_field.dart';

/// Right-side settings rail beside the editor: model & voice, styling, run
/// options, and a Narrate action. Every control writes straight to
/// [AppController], which notifies the editor so the status-bar estimate stays
/// live. [onClose] hides the rail (wired by the editor's toggle).
class InspectorRail extends StatefulWidget {
  const InspectorRail({super.key, required this.controller, this.onClose});

  final AppController controller;

  /// Called when the user taps the collapse control at the top of the rail.
  final VoidCallback? onClose;

  @override
  State<InspectorRail> createState() => _InspectorRailState();
}

class _InspectorRailState extends State<InspectorRail> {
  late final TextEditingController _voiceRaw;
  late final TextEditingController _accent;
  late final TextEditingController _style;
  late final TextEditingController _prefix;
  late final TextEditingController _minWords;
  late final TextEditingController _sampleLen;
  late final TextEditingController _outDir;

  String? _guardMessage;
  Timer? _guardTimer;

  /// Set while applying controller state into the local fields; prevents the
  /// controller notify -> field write -> onChanged -> controller write loop
  /// from echoing.
  bool _syncing = false;

  AppController get _controller => widget.controller;

  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  List<(String, String)> get _modelItems => [
        for (final p in effectiveModels(_controller.voiceConfig))
          (p.alias, '${p.alias} — ${p.id}'),
      ];

  List<(String, String)> get _voiceItems {
    final entries = voiceEntries(
      model: _controller.profile,
      config: _controller.voiceConfig,
    );
    return [
      for (final e in entries) (e.label, e.label),
    ];
  }

  @override
  void initState() {
    super.initState();
    _voiceRaw = TextEditingController(text: _controller.voice);
    _accent = TextEditingController(text: _controller.accent);
    _style = TextEditingController(text: _controller.style);
    _prefix = TextEditingController(text: _controller.passagePrefix);
    _minWords = TextEditingController(text: _controller.minWords.toString());
    _sampleLen =
        TextEditingController(text: _controller.sampleLen?.toString() ?? '');
    _outDir = TextEditingController(text: _controller.outDir);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    for (final c in [
      _voiceRaw,
      _accent,
      _style,
      _prefix,
      _minWords,
      _sampleLen,
      _outDir,
    ]) {
      c.dispose();
    }
    _guardTimer?.cancel();
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
      if (_minWords.text != _controller.minWords.toString()) {
        _minWords.text = _controller.minWords.toString();
      }
      if (_sampleLen.text != (_controller.sampleLen?.toString() ?? '')) {
        _sampleLen.text = _controller.sampleLen?.toString() ?? '';
      }
      if (_outDir.text != _controller.outDir) {
        _outDir.text = _controller.outDir;
      }
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

  void _onMinWordsChanged(String value) {
    if (_syncing) return;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    _controller.minWords = parsed;
  }

  void _onSampleLenChanged(String value) {
    if (_syncing) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _controller.sampleLen = null;
      return;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return;
    _controller.sampleLen = parsed;
  }

  void _onOutDirChanged(String value) {
    if (_syncing) return;
    _controller.outDir = value;
  }

  void _onNarratePressed() {
    final reason = _controller.narrateBlockReason();
    if (reason != null) {
      _showGuard(reason);
      return;
    }
    _controller.onNarrate?.call();
  }

  void _showGuard(String message) {
    _guardTimer?.cancel();
    setState(() => _guardMessage = message);
    _guardTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _guardMessage = null);
    });
  }

  Color _accentColor() => _isMac
      ? CupertinoTheme.brightnessOf(context) == Brightness.dark
          ? CupertinoColors.activeBlue
          : CupertinoColors.systemBlue
      : Theme.of(context).colorScheme.primary;

  Color _mutedColor() => _isMac
      ? CupertinoColors.systemGrey
      : Theme.of(context).colorScheme.onSurfaceVariant;

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _mutedColor(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('inspectorRail'),
      width: 300,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: _isMac
                ? CupertinoColors.separator
                : Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if (_guardMessage != null) _buildGuardBanner(_guardMessage!),
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
                _buildNarrateButton(),
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
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Settings',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _accentColor(),
              ),
            ),
          ),
          PlatformIconButton(
            key: const Key('railCloseButton'),
            tooltip: 'Hide settings',
            icon: Icon(
              _isMac
                  ? CupertinoIcons.sidebar_right
                  : Icons.settings_overscan,
            ),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildGuardBanner(String message) {
    final background = _isMac
        ? CupertinoColors.systemRed.withValues(alpha: 0.12)
        : Theme.of(context).colorScheme.errorContainer;
    final foreground = _isMac
        ? CupertinoColors.systemRed
        : Theme.of(context).colorScheme.onErrorContainer;
    return Container(
      key: const Key('railGuard'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Text(
        message,
        key: const Key('railGuardMessage'),
        style: TextStyle(fontSize: 12, color: foreground),
      ),
    );
  }

  Widget _buildModelVoiceSection() {
    return PlatformSection(
      title: 'Model & voice',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Model'),
          PlatformDropdown<String>(
            key: const Key('modelDropdown'),
            value: _controller.modelAlias,
            items: _modelItems,
            onChanged: (alias) => _controller.changeModel(alias),
          ),
          _label('Voice alias'),
          PlatformDropdown<String>(
            key: const Key('voiceDropdown'),
            value: _selectedVoiceLabel,
            items: _voiceItems,
            hint: 'Pick a known voice or alias',
            onChanged: (label) => _controller.applyVoiceLabel(label),
          ),
          _label('Raw voice id'),
          PlatformTextField(
            key: const Key('voiceRawField'),
            controller: _voiceRaw,
            onChanged: _onVoiceRawChanged,
            hintText: 'free-form id or provider voice',
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
        children: [
          for (final option in options) _buildModelOption(option),
        ],
      ),
    );
  }

  /// The model-option keys this app version binds to narration settings.
  static const _bindableModelOptionKeys = {
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
              Expanded(child: Text(option.label)),
              PlatformSwitch(
                key: Key('${option.key}Switch'),
                value: _modelOptionBool(option.key),
                onChanged: (v) => _setModelOptionBool(option.key, v),
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
          _label('Min words per chunk'),
          PlatformTextField(
            key: const Key('minWordsField'),
            controller: _minWords,
            onChanged: _onMinWordsChanged,
            keyboardType: TextInputType.number,
          ),
          _label('Sample length (optional)'),
          PlatformTextField(
            key: const Key('sampleLenField'),
            controller: _sampleLen,
            onChanged: _onSampleLenChanged,
            keyboardType: TextInputType.number,
          ),
          _label('Output directory'),
          PlatformTextField(
            key: const Key('outDirField'),
            controller: _outDir,
            onChanged: _onOutDirChanged,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Resume (skip completed chunks)'),
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

  Widget _buildNarrateButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: PlatformButton(
        key: const Key('railNarrateButton'),
        onPressed: _onNarratePressed,
        icon: Icon(_isMac ? CupertinoIcons.mic : Icons.mic),
        child: const Text('Narrate'),
      ),
    );
  }
}