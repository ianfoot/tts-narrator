import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../platform/platform_page.dart';
import '../platform/widgets/platform_button.dart';
import '../platform/widgets/platform_text_field.dart';

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

  Color _textColor() => _isMac
      ? CupertinoTheme.brightnessOf(context) == Brightness.dark
          ? CupertinoColors.white
          : CupertinoColors.black
      : Theme.of(context).colorScheme.onSurface;

  Color _mutedColor() => _isMac
      ? CupertinoColors.systemGrey
      : Theme.of(context).colorScheme.onSurfaceVariant;

  @override
  Widget build(BuildContext context) {
    return PlatformPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          _buildToolbar(),
          if (_guardMessage != null) _buildGuardBanner(_guardMessage!),
          Expanded(child: _buildEditor()),
          _buildStatusBar(),
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
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: _accentColor(),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_controller.documentName}$mutable',
            style: TextStyle(fontSize: 12, color: _mutedColor()),
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
      key: const Key('narrateGuard'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: background,
      child: Text(
        message,
        key: const Key('narrateGuardMessage'),
        style: TextStyle(fontSize: 13, color: foreground),
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
        style: TextStyle(fontSize: 15, height: 1.4, color: _textColor()),
      ),
    );
  }

  Widget _buildStatusBar() {
    final words = _controller.wordCount;
    final chars = _controller.charCount;
    final chunks = _controller.plannedChunks.length;
    final minutes = _controller.estimatedMinutes;
    final cost = formatCostUsd(_controller.estimatedCostUsd);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: _isMac ? CupertinoColors.separator : Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$words words · $chars chars',
            key: const Key('editorWordCharCount'),
            style: TextStyle(fontSize: 12, color: _mutedColor()),
          ),
          const Spacer(),
          Text(
            '$chunks chunks · ${minutes.toStringAsFixed(1)} min · $cost',
            key: const Key('editorEstimate'),
            style: TextStyle(fontSize: 12, color: _mutedColor()),
          ),
        ],
      ),
    );
  }
}