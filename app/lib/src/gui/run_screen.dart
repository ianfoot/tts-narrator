import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

class _Chunk {
  _Chunk({required this.index, required this.paragraph});

  final int index;
  final String paragraph;
  String? filePath;
  bool resumed = false;
}

/// Run screen: dry-run plan preview + cost, then Narrate / Cancel with live
/// per-chunk progress and in-app playback.
class RunScreen extends StatefulWidget {
  const RunScreen({super.key, required this.config});

  /// Immutable narration configuration built by the settings form.
  final NarrationConfig config;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  List<_Chunk> _chunks = const [];
  String? _planError;
  bool _running = false;
  String? _error;
  bool _finished = false;
  bool _stopped = false;
  AbortToken? _token;
  AudioPlayer? _player;
  int? _playingIndex;

  NarrationConfig get _config => widget.config;

  @override
  void initState() {
    super.initState();
    try {
      final paragraphs = planChunks(_config);
      _chunks = [
        for (var i = 0; i < paragraphs.length; i++)
          _Chunk(index: i, paragraph: paragraphs[i]),
      ];
    } on Exception catch (e) {
      _planError = e.toString();
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String _audioPathFor(int index, int total) {
    final ext = _config.profile.format == 'pcm' ? 'wav' : 'mp3';
    final pad = total.toString().length;
    final baseName = '${inputStem(_config.inputPath)}'
        '_${(index + 1).toString().padLeft(pad, '0')}.$ext';
    return '${outputDirPath(_config)}${Platform.pathSeparator}$baseName';
  }

  Future<void> _narrate() async {
    final token = AbortToken();
    setState(() {
      _running = true;
      _error = null;
      _finished = false;
      _stopped = false;
      _token = token;
      for (final c in _chunks) {
        c.resumed = false;
      }
    });
    try {
      await narrate(
        _config,
        onProgress: (i, total, paragraph, {resumed = false}) {
          if (!mounted) return;
          setState(() {
            _chunks[i].filePath ??= _audioPathFor(i, total);
          });
        },
        onChunkComplete: (i, filePath, {resumed = false}) {
          if (!mounted) return;
          setState(() {
            _chunks[i].filePath = filePath;
            _chunks[i].resumed = resumed;
          });
        },
        abort: token,
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _finished = true;
      });
    } on AbortException {
      if (!mounted) return;
      setState(() {
        _running = false;
        _stopped = true;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e.toString();
      });
    }
  }

  void _cancel() {
    _token?.cancel();
  }

  Future<void> _togglePlay(_Chunk chunk) async {
    final path = chunk.filePath;
    if (path == null || !File(path).existsSync()) return;
    if (_playingIndex == chunk.index) {
      await _player?.stop();
      if (mounted) setState(() => _playingIndex = null);
      return;
    }
    await _player?.stop();
    final player = _player ??= AudioPlayer();
    await player.play(DeviceFileSource(path));
    if (mounted) setState(() => _playingIndex = chunk.index);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _config.profile;
    final minutes = estimateMinutes(_chunks.map((c) => c.paragraph).toList());
    return Scaffold(
      appBar: AppBar(title: Text('Narrate — ${inputStem(_config.inputPath)}')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SummaryCard(
                    model: '${profile.alias} (${profile.id})',
                    format: profile.format,
                    chunks: _chunks.length,
                    minutes: minutes,
                    cost: estimateCostUsd(
                      _config.pricing,
                      _chunks.map((c) => c.paragraph).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_planError != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('Plan failed: $_planError'),
                      ),
                    )
                  else
                    for (final chunk in _chunks) _buildChunkTile(chunk, context),
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('Narration failed: $_error'),
                      ),
                    ),
                  if (_stopped)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Narration was stopped.'),
                      ),
                    ),
                  if (_finished)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Narration complete.'),
                      ),
                    ),
                ],
              ),
            ),
            _buildActionBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildChunkTile(_Chunk chunk, BuildContext context) {
    final words = chunk.paragraph.split(RegExp(r'\s+')).length;
    final preview = chunk.paragraph.length > 90
        ? '${chunk.paragraph.substring(0, 90)}…'
        : chunk.paragraph;
    final playable = chunk.filePath != null && File(chunk.filePath!).existsSync();
    final icon = _playingIndex == chunk.index
        ? Icons.stop_circle_outlined
        : Icons.play_circle_outline;
    return ListTile(
      leading: _chunkLeading(chunk),
      title: Text('[${chunk.index + 1}/${_chunks.length}] $preview'),
      subtitle: Text(
        words == 1 ? '$words word' : '$words words',
      ),
      trailing: chunk.resumed || playable
          ? IconButton(
              tooltip: chunk.resumed ? 'Resumed — tap to play' : 'Play',
              icon: Icon(icon),
              onPressed: () => _togglePlay(chunk),
            )
          : null,
    );
  }

  Widget _chunkLeading(_Chunk chunk) {
    if (chunk.resumed) {
      return const Icon(Icons.replay_circle_filled, color: Colors.orange);
    }
    if (_playingIndex == chunk.index) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return const Icon(Icons.radio_button_unchecked);
  }

  Widget _buildActionBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: _running
          ? Row(
              children: [
                const Expanded(
                  child: LinearProgressIndicator(),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.stop),
                  label: const Text('Cancel'),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('startNarrationButton'),
                    onPressed: (_chunks.isEmpty && _planError != null)
                        ? null
                        : _narrate,
                    icon: const Icon(Icons.mic),
                    label: Text(_running ? 'Running…' : 'Narrate'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.model,
    required this.format,
    required this.chunks,
    required this.minutes,
    required this.cost,
  });

  final String model;
  final String format;
  final int chunks;
  final double minutes;
  final double cost;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Model: $model'),
            Text('Format: $format'),
            Text('Chunks: $chunks'),
            Text(
              'Estimated: ${minutes.toStringAsFixed(1)} min, '
              '${formatCostUsd(cost)}',
            ),
          ],
        ),
      ),
    );
  }
}