import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'config_service.dart';
import 'run_screen.dart';

/// Single-screen settings form: pick a source text, an OpenRouter TTS model
/// and voice, narration styling options, and launch the run screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.configPath});

  /// Optional voice-config path (defaults to the platform config dir).
  final String? configPath;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ConfigService _configService;
  late VoiceConfig _voiceConfig;

  late final TextEditingController _inputPath;
  late final TextEditingController _voiceRaw;
  late final TextEditingController _accent;
  late final TextEditingController _style;
  late final TextEditingController _prefix;
  late final TextEditingController _minWords;
  late final TextEditingController _sampleLen;
  late final TextEditingController _outDir;

// Cold-start default: the fish bootstrap + its friendly voice, replaced by
  // the config's "defaults" when one is configured.
  String _modelAlias = kDefaultProfile.profile.alias;
  String? _selectedVoiceLabel = kDefaultProfile.voiceLabel;
  bool _useCalmTag = false;
  bool _resume = false;

  TtsModelProfile get _profile => profileFor(_modelAlias, _voiceConfig)!;

  List<VoiceEntry> get _voiceEntries =>
      voiceEntries(model: _profile, config: _voiceConfig);

  /// The configured/compiled default voice for [model], or null when none.
  (String, String)? _defaultFor(TtsModelProfile model) {
    try {
      return defaultVoiceFor(model, _voiceConfig);
    } on VoiceConfigError {
      return null;
    }
  }

  @override
void initState() {
    super.initState();
    final defaults = NarrationConfig(
      inputPath: '',
      profile: kDefaultProfile.profile,
      voice: kDefaultProfile.voice,
    );
    _configService = ConfigService(path: widget.configPath);
    _voiceConfig = _configService.load();
    final bootstrap = _defaultFor(kDefaultProfile.profile) ??
        (kDefaultProfile.voice, kDefaultProfile.voiceLabel);
    _inputPath = TextEditingController();
    _voiceRaw = TextEditingController(text: bootstrap.$1);
    _selectedVoiceLabel = bootstrap.$2;
    _accent = TextEditingController(text: defaults.accent);
    _style = TextEditingController(text: defaults.style);
    _prefix = TextEditingController(text: defaults.passagePrefix);
    _minWords = TextEditingController(text: defaults.minWords.toString());
    _sampleLen = TextEditingController();
    _outDir = TextEditingController(text: defaults.outDir);
  }

  @override
  void dispose() {
    for (final c in [
      _inputPath,
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
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickInputFile() async {
    const group = XTypeGroup(label: 'Text', extensions: ['txt']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file != null) {
      setState(() => _inputPath.text = file.path);
    }
  }

  void _changeModel(String alias) {
    final previous = _profile;
    final next = profileFor(alias, _voiceConfig)!;
    setState(() {
      final raw = _voiceRaw.text.trim();
      final previousDefault = _defaultFor(previous)?.$1;
      if (raw.isEmpty || raw == previousDefault) {
        final def = _defaultFor(next);
        if (def != null) {
          _voiceRaw.text = def.$1;
          _selectedVoiceLabel = def.$2;
        } else {
          _voiceRaw.text = '';
          _selectedVoiceLabel = null;
        }
      }
      _modelAlias = alias;
    });
  }

  void _applyVoiceLabel(String label) {
    final (id, _) = _voiceConfig.resolveVoice(_profile.alias, label);
    setState(() {
      _selectedVoiceLabel = label;
      _voiceRaw.text = id;
    });
  }

  NarrationConfig _buildConfig() {
    final inputPath = _inputPath.text.trim();
    final raw = _voiceRaw.text.trim();
    String voice;
    String? label;
    if (raw.isEmpty) {
      final def = _defaultFor(_profile);
      if (def == null) {
        throw FormatException(
          'No voice selected for "${_profile.alias}" — pick an alias or set a '
          'default in the voice config.',
        );
      }
      voice = def.$1;
      label = def.$2 == def.$1 ? null : def.$2;
    } else {
      // Voices pass through unvalidated (providers add/remove voices; testing
      // arbitrary ids is a feature).
      final (voiceId, voiceLabel) = _voiceConfig.resolveVoice(
        _profile.alias,
        raw,
      );
      voice = voiceId;
      label = (_selectedVoiceLabel != null && voiceId == raw)
          ? _selectedVoiceLabel
          : (voiceLabel != voiceId ? voiceLabel : null);
    }
    final minWords = int.tryParse(_minWords.text.trim()) ?? 30;
    final sampleRaw = _sampleLen.text.trim();
    return NarrationConfig(
      inputPath: inputPath,
      profile: _profile,
      voice: voice,
      voiceLabel: label,
      accent: _accent.text,
      style: _style.text,
      useCalmTag: _useCalmTag,
      passagePrefix: _prefix.text,
      minWords: minWords,
      sampleLen: sampleRaw.isEmpty ? null : int.tryParse(sampleRaw),
      outDir: _outDir.text.trim().isEmpty ? 'output' : _outDir.text.trim(),
      resume: _resume,
      // Read-only use of the shared config's api_key (the GUI never writes it);
      // absent there, TtsClient falls back to OPENROUTER_API_KEY.
      apiKey: _voiceConfig.apiKey,
      pricing: _voiceConfig.pricingFor(_profile.alias),
    );
  }

  void _submit() {
    final inputPath = _inputPath.text.trim();
    if (inputPath.isEmpty) {
      _snack('Choose a source text to narrate.');
      return;
    }
    if (!File(inputPath).existsSync()) {
      _snack('Input not found: "$inputPath".');
      return;
    }
    final NarrationConfig config;
    try {
      config = _buildConfig();
    } on FormatException catch (e) {
      _snack(e.message);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => RunScreen(config: config)));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _voiceEntries;
    final selected = entries.any((e) => e.label == _selectedVoiceLabel)
        ? _selectedVoiceLabel
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('TTS Narrator')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Source', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('inputPathField'),
                    controller: _inputPath,
                    decoration: const InputDecoration(
                      labelText: 'Text to narrate (.txt)',
                      hintText: '/path/to/story.txt',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickInputFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Browse…'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Model & voice',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              child: DropdownButton<String>(
                key: const Key('modelDropdown'),
                isExpanded: true,
                value: _modelAlias,
                underline: const SizedBox.shrink(),
                items: [
                  for (final p in effectiveModels(_voiceConfig))
                    DropdownMenuItem(
                      value: p.alias,
                      child: Text('${p.alias} — ${p.id}'),
                    ),
                ],
                onChanged: (v) => v == null ? null : _changeModel(v),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Voice (pick an alias)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: DropdownButton<String>(
                      key: const Key('voiceDropdown'),
                      isExpanded: true,
                      value: selected,
                      hint: const Text('Pick a known voice or alias'),
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final e in entries)
                          DropdownMenuItem(
                            value: e.label,
                            child: Text(e.label),
                          ),
                      ],
                      onChanged: (v) => v == null ? null : _applyVoiceLabel(v),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('voiceRawField'),
                    controller: _voiceRaw,
                    onChanged: (_) {
                      if (_selectedVoiceLabel != null) {
                        final (id, _) = _voiceConfig.resolveVoice(
                          _profile.alias,
                          _selectedVoiceLabel!,
                        );
                        if (_voiceRaw.text != id) {
                          setState(() => _selectedVoiceLabel = null);
                        }
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Raw voice id',
                      hintText: 'free-form id or provider voice',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Pick a known voice or alias on the left, or type a raw provider id directly (kokoro/fish are free-form).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Styling', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _accent,
              decoration: const InputDecoration(
                labelText: 'Accent',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _style,
              decoration: const InputDecoration(
                labelText: 'Style / register',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prefix,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Passage prefix',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Prepend [calm] tag (Gemini only)'),
              value: _useCalmTag,
              onChanged: (v) => setState(() => _useCalmTag = v),
            ),
            const SizedBox(height: 8),
            Text('Run', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minWords,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Min words per chunk',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sampleLen,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Sample length (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _outDir,
              decoration: const InputDecoration(
                labelText: 'Output directory',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Resume (skip chunks in an existing manifest)'),
              value: _resume,
              onChanged: (v) => setState(() => _resume = v),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('narrateButton'),
              onPressed: _submit,
              icon: const Icon(Icons.mic),
              label: const Text('Narrate →'),
            ),
          ],
        ),
      ),
    );
  }
}
