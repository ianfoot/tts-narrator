import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../platform/platform_page.dart';
import '../platform/widgets/platform_button.dart';
import '../platform/widgets/platform_icon_button.dart';
import '../platform/widgets/platform_text_field.dart';
import '../settings/inspector_rail.dart';
import '../theme/app_tokens.dart';

/// Editor-first home screen: a large empty multiline text field (the document),
/// a toolbar (Open / Narrate), and a live status bar
/// (words · chars · chunks · est. minutes · est. cost).
///
/// All command dispatch goes through [AppController]; the screen only renders
/// controller state and surfaces controller guards (e.g. the empty-text
/// Narrate guard) as a transient inline banner.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _textController;
  String? _guardMessage;
  Timer? _guardTimer;
  bool _railVisible = true;

  AppController get _controller => widget.controller;

  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: _controller.text);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _textController.dispose();
    _guardTimer?.cancel();
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {
      if (_textController.text != _controller.text) {
        _textController.text = _controller.text;
      }
    });
  }

  void _onTextChanged(String value) => _controller.setText(value);

  void _onOpenPressed() => _controller.onOpen?.call();

  void _onNarratePressed() {
    final reason = _controller.narrateBlockReason();
    if (reason != null) {
      _showGuard(reason);
      return;
    }
    // Dispatch through the Narrate slot (AppRoot navigates to the run view).
    _controller.onNarrate?.call();
  }

  void _toggleRail() => setState(() => _railVisible = !_railVisible);

  void _showGuard(String message) {
    _guardTimer?.cancel();
    setState(() => _guardMessage = message);
    _guardTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _guardMessage = null);
    });
  }

  AppTokens get _tokens => AppTokens.of(context);

  @override
  Widget build(BuildContext context) {
    return PlatformPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          _buildToolbar(),
          if (_controller.configWarnings.isNotEmpty)
            _buildConfigWarningsBanner(_controller.configWarnings),
          if (_guardMessage != null) _buildGuardBanner(_guardMessage!),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildEditor()),
                      _buildStatusBar(),
                    ],
                  ),
                ),
                if (_railVisible)
                  InspectorRail(
                    controller: _controller,
                    onClose: () => setState(() => _railVisible = false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final mutable = _controller.dirty ? ' • modified' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TTS Narrator',
            style: _tokens.typography.screenTitle.copyWith(
              color: _tokens.colors.accentPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_controller.documentName}$mutable',
            style: _tokens.typography.mono.copyWith(
              color: _tokens.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          PlatformButton(
            key: const Key('editorOpenButton'),
            onPressed: _onOpenPressed,
            style: PlatformButtonStyle.outlined,
            icon: Icon(_isMac ? CupertinoIcons.folder : Icons.folder_open),
            child: const Text('Open'),
          ),
          const SizedBox(width: 8),
          PlatformButton(
            key: const Key('editorNarrateButton'),
            onPressed: _onNarratePressed,
            icon: Icon(_isMac ? CupertinoIcons.mic : Icons.mic),
            child: const Text('Narrate'),
          ),
          const Spacer(),
          PlatformIconButton(
            key: const Key('railToggleButton'),
            tooltip: 'Show / hide settings',
            icon: Icon(
              _isMac
                  ? (_railVisible
                        ? CupertinoIcons.line_horizontal_3_decrease_circle
                        : CupertinoIcons.line_horizontal_3_decrease_circle_fill)
                  : (_railVisible ? Icons.settings : Icons.settings_outlined),
            ),
            onPressed: _toggleRail,
          ),
        ],
      ),
    );
  }

  Widget _buildGuardBanner(String message) {
    final colors = _tokens.colors;
    final background = colors.accentError.withValues(alpha: 0.12);
    final foreground = colors.accentError;
    return Container(
      key: const Key('narrateGuard'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: background,
      child: Text(
        message,
        key: const Key('narrateGuardMessage'),
        style: _tokens.typography.body.copyWith(color: foreground),
      ),
    );
  }

  /// Persistent, non-fatal notice that one or more model config files were
  /// skipped on load (e.g. a malformed model). Renders alongside the toolbar so
  /// the user knows why a model is missing from the picker.
  Widget _buildConfigWarningsBanner(List<String> warnings) {
    final colors = _tokens.colors;
    final background = colors.accentWarning.withValues(alpha: 0.12);
    final foreground = colors.accentWarning;
    return Container(
      key: const Key('configWarnings'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: background,
      child: Text(
        warnings.join('\n'),
        key: const Key('configWarningsMessage'),
        style: _tokens.typography.body.copyWith(color: foreground),
      ),
    );
  }

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: PlatformTextField(
        key: const Key('editorTextField'),
        controller: _textController,
        onChanged: _onTextChanged,
        hintText: 'Type or paste the text to narrate here…',
        maxLines: null,
        expands: true,
        autofocus: true,
        // Editor typography moves to the serif stack in Task 2; keep the
        // current reading size/leading here, only tokenize the color.
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: _tokens.colors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final words = _controller.wordCount;
    final chars = _controller.charCount;
    final chunks = _controller.plannedChunks.length;
    final minutes = _controller.estimatedMinutes;
    final cost = formatCostUsd(_controller.estimatedCostUsd);
    final colors = _tokens.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$words words · $chars chars',
            key: const Key('editorWordCharCount'),
            style: _tokens.typography.mono.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            '$chunks chunks · ${minutes.toStringAsFixed(1)} min · $cost',
            key: const Key('editorEstimate'),
            style: _tokens.typography.mono.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}