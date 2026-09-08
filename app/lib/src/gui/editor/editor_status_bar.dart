import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../controller/app_controller.dart';
import '../theme/app_text_tokens.dart' show TextTokens, fillTextTemplate;
import '../theme/app_tokens.dart';

/// Bottom status bar (JSON UI Schema `status_bar`): the word/char counts, the
/// current output folder (left-truncated when tight), and the estimate readout.
/// Listens to [AppController] so the readouts stay live without the parent
/// rebuilding, mirroring [EditorToolbar].
class EditorStatusBar extends StatefulWidget {
  const EditorStatusBar({super.key, required this.controller});

  final AppController controller;

  @override
  State<EditorStatusBar> createState() => _EditorStatusBarState();
}

class _EditorStatusBarState extends State<EditorStatusBar> {
  static const _tickerDuration = Duration(milliseconds: 100);

  /// Pin the count grouping so the status bar renders the same separators on
  /// every machine; the GUI is English-only.
  static final NumberFormat _countFormat = NumberFormat.decimalPattern('en_US');

  AppController get controller => widget.controller;

  AppTokens get tokens => AppTokens.of(context);

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = tokens.colors;
    // Readouts (word/char counts, output path, estimate) share one Tier 3
    // metric style: monospace textSecondary at 75%, so the middle path matches
    // the flanking metrics instead of blending into the footer.
    final monoReadout = tokens.typography.mono.copyWith(
      color: colors.textSecondary.withValues(alpha: 0.75),
    );
    final words = _countFormat.format(controller.wordCount);
    final chars = _countFormat.format(controller.charCount);
    final segments = controller.plannedSegments.length;
    final minutes = controller.estimatedMinutes.round();
    final cost = formatCostUsd(controller.estimatedCostUsd);
    final segmentLabel =
        segments == 1
            ? TextTokens.core_plurals_segment
            : TextTokens.core_plurals_segments;
    return Container(
      key: const Key('statusBar'),
      height: AppMetrics.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: _tickerDuration,
              child: Text(
                fillTextTemplate(
                  TextTokens.gui_editor_statusBar_wordCharCount,
                  {'words': words, 'chars': chars},
                ),
                key: ValueKey('$words-$chars'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: monoReadout,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final text = _leftTruncate(
                  controller.outDir,
                  monoReadout,
                  constraints.maxWidth,
                );
                return Text(
                  text,
                  key: const Key('statusOutDir'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: monoReadout,
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          AnimatedSwitcher(
            duration: _tickerDuration,
            child: KeyedSubtree(
              key: ValueKey('$segments-$minutes-$cost'),
              child: Text(
                fillTextTemplate(
                  TextTokens.gui_editor_statusBar_estimate,
                  {
                    'segments': segments,
                    'segmentLabel': segmentLabel,
                    'minutes': minutes,
                    'cost': cost,
                  },
                ),
                key: const Key('editorEstimate'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: monoReadout,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns [s] left-truncated with a leading ellipsis if it would not
/// fit within [maxWidth] when rendered with [style]. The leaf (rightmost
/// part) is preserved, so the actual folder name stays visible when the
/// full path is too long for the status bar slot.
String _leftTruncate(String s, TextStyle style, double maxWidth) {
  if (maxWidth <= 0 || s.isEmpty) return s;
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  if (tp.width <= maxWidth) return s;
  const ellipsis = '\u2026';
  for (var i = 1; i < s.length; i++) {
    final candidate = '$ellipsis${s.substring(i)}';
    tp.text = TextSpan(text: candidate, style: style);
    tp.layout(maxWidth: double.infinity);
    if (tp.width <= maxWidth) return candidate;
  }
  return ellipsis;
}
