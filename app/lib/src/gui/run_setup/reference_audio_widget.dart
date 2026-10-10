import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../controller/app_controller.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import '../widgets/disclosure.dart';
import 'run_setup_labels.dart';

/// Voice cloning control for models that declare `"sends_reference_audio"`.
///
/// The clip is a path on the provider's filesystem, not an upload, so this
/// works only against a server that shares one with the app — in practice the
/// bundled local provider. With a clip chosen the clip replaces the voice, so
/// the voice picker hides its dropdown and this control names the clip in its
/// caption instead.
class ReferenceAudioWidget extends StatefulWidget {
  const ReferenceAudioWidget({super.key, required this.controller});

  final AppController controller;

  @override
  State<ReferenceAudioWidget> createState() => _ReferenceAudioWidgetState();
}

class _ReferenceAudioWidgetState extends State<ReferenceAudioWidget> {
  static const _extensions = ['wav', 'mp3', 'flac', 'm4a', 'ogg', 'aac'];

  late final TextEditingController _transcript;
  bool _expanded = false;
  bool _syncing = false;

  AppController get _controller => widget.controller;
  AppTokens get _tokens => AppTokens.of(context);

  @override
  void initState() {
    super.initState();
    _transcript = TextEditingController(text: _controller.referenceAudioText);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _transcript.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      _syncing = true;
      if (_transcript.text != _controller.referenceAudioText) {
        _transcript.text = _controller.referenceAudioText;
      }
      _syncing = false;
    });
  }

  void _onTranscriptChanged(String value) {
    if (_syncing) return;
    _controller.referenceAudioText = value;
  }

  Future<void> _chooseClip() async {
    final l10n = AppLocalizations.of(context);
    final group = XTypeGroup(label: l10n.gui_run_setup_audioFileTypeGroup,
        extensions: _extensions);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    try {
      _controller.referenceAudioPath = file.path;
    } on FileSystemException {
      // The picker only returns existing files; ignore races.
    }
  }

  void _clearClip() {
    _controller.referenceAudioPath = null;
    _controller.referenceAudioText = '';
  }

  /// The last path segment, which is what a person recognises their clip by.
  static String _fileName(String path) =>
      Uri.file(path).pathSegments.last;

  String _caption(AppLocalizations l10n) {
    final path = _controller.referenceAudioPath;
    if (path == null || path.isEmpty) {
      return l10n.gui_run_setup_voiceCloningCaptionOverrides;
    }
    return l10n.gui_run_setup_voiceCloningCaptionCloned(_fileName(path));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final path = _controller.referenceAudioPath;
    final hasClip = path != null && path.isNotEmpty;
    if (!_controller.takesReferenceAudio) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Disclosure(
        key: const Key('referenceAudioDisclosure'),
        tooltip: l10n.gui_run_setup_voiceCloningTooltip,
        label: l10n.gui_run_setup_voiceCloningLabel,
        expanded: _expanded,
        caption: _caption(l10n),
        onToggle: (value) => setState(() => _expanded = value),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            runSetupFieldLabel(_tokens, l10n.gui_run_setup_referenceClipLabel),
            const SizedBox(height: 6),
            Row(
              children: [
                AppButton(
                  key: const Key('referenceAudioChooseButton'),
                  style: AppButtonStyle.outlined,
                  compact: true,
                  onPressed: _chooseClip,
                  child: Text(l10n.gui_run_setup_referenceClipChoose),
                ),
                if (hasClip) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fileName(path),
                      key: const Key('referenceAudioName'),
                      overflow: TextOverflow.ellipsis,
                      style: _tokens.typography.body
                          .copyWith(color: _tokens.colors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    key: const Key('referenceAudioClearButton'),
                    style: AppButtonStyle.outlined,
                    compact: true,
                    onPressed: _clearClip,
                    child: Text(l10n.gui_run_setup_referenceClipClear),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            runSetupFieldLabel(
                _tokens, l10n.gui_run_setup_referenceTextLabel),
            const SizedBox(height: 6),
            AppTextField(
              key: const Key('referenceTextField'),
              controller: _transcript,
              onChanged: _onTranscriptChanged,
              maxLines: 3,
              hintText: l10n.gui_run_setup_referenceTextHint,
            ),
          ],
        ),
      ),
    );
  }
}