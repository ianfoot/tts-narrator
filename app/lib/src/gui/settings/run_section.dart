import 'package:flutter/material.dart';

import '../controller/app_controller.dart';
import '../platform/widgets/platform_section.dart';
import '../platform/widgets/platform_slider.dart';
import '../platform/widgets/platform_switch.dart';
import '../platform/widgets/platform_text_field.dart';
import '../theme/app_text_tokens.dart' show TextTokens;
import '../theme/app_tokens.dart';
import 'settings_labels.dart';

/// The "Run" section of the settings rail: whole-file toggle, the minimum
/// words-per-segment slider (hidden while whole-file is on), sample mode with
/// its inline segment count, and the skip-completed-segments toggle.
class RunSection extends StatefulWidget {
  const RunSection({super.key, required this.controller});

  final AppController controller;

  @override
  State<RunSection> createState() => _RunSectionState();
}

class _RunSectionState extends State<RunSection> {
  late final TextEditingController _sampleLen;

  /// Set while applying controller state into the local fields; prevents the
  /// controller notify -> field write -> onChanged -> controller write loop
  /// from echoing.
  bool _syncing = false;

  /// Whether sample mode is on (revealing the inline segment count input).
  bool _sampleOn = false;

  AppController get _controller => widget.controller;

  AppTokens get _tokens => AppTokens.of(context);

  int get _minWords => _controller.minWords;

  @override
  void initState() {
    super.initState();
    _sampleLen = TextEditingController(
      text: _controller.sampleLen?.toString() ?? '',
    );
    _sampleOn = _controller.sampleLen != null;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _sampleLen.dispose();
    super.dispose();
  }

  /// Pushes controller changes back into the local fields. The rail is the
  /// only writer to these values, so this mostly no-ops.
  void _onControllerChanged() {
    setState(() {
      _syncing = true;
      if (_sampleLen.text != (_controller.sampleLen?.toString() ?? '')) {
        _sampleLen.text = _controller.sampleLen?.toString() ?? '';
      }
      _sampleOn = _controller.sampleLen != null;
      _syncing = false;
    });
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

  @override
  Widget build(BuildContext context) {
    return PlatformSection(
      title: TextTokens.gui_settings_runSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_controller.wholeFileAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: settingsControlLabel(
                      _tokens,
                      TextTokens.gui_settings_sendWholeFile,
                    ),
                  ),
                  PlatformSwitch(
                    key: const Key('wholeFileSwitch'),
                    tooltip: TextTokens.gui_settings_sendWholeFileTooltip,
                    value: _controller.sendWholeFile,
                    onChanged: (v) => _controller.sendWholeFile = v,
                  ),
                ],
              ),
            ),
          if (!_controller.sendWholeFile) ...[
            settingsFieldLabel(_tokens, TextTokens.gui_settings_minWordsLabel),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PlatformSlider(
                    key: const Key('minWordsSlider'),
                    tooltip: TextTokens.gui_settings_minWordsSliderTooltip,
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
                  child: Text('$_minWords', style: _tokens.typography.mono),
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: settingsControlLabel(
                    _tokens,
                    TextTokens.gui_settings_sampleMode,
                  ),
                ),
                PlatformSwitch(
                  key: const Key('sampleSwitch'),
                  tooltip: TextTokens.gui_settings_sampleModeTooltip,
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
                      TextTokens.gui_settings_narrateFirstSegments,
                      style: _tokens.typography.body,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: PlatformTextField(
                      key: const Key('sampleLenField'),
                      tooltip: TextTokens.gui_settings_sampleLenFieldTooltip,
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
                  child: settingsControlLabel(
                    _tokens,
                    TextTokens.gui_settings_skipCompletedSegments,
                  ),
                ),
                PlatformSwitch(
                  key: const Key('resumeSwitch'),
                  tooltip: TextTokens.gui_settings_resumeTooltip,
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
}
