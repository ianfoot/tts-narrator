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
  late final TextEditingController _apiKey;
  late final TextEditingController _aliasLabel;

  String _modelAlias = kGeminiProfile.alias;
  String? _selectedVoiceLabel;
  bool _useCalmTag = false;
  bool _resume = false;

  TtsModelProfile get _profile => profileFor(_modelAlias)!;

  List<VoiceEntry> get _voiceEntries =>
      voiceEntries(model: _profile, config: _voiceConfig);

  @override
  void initState() {
    super.initState();
    final defaults = NarrationConfig(
      inputPath: '',
      profile: kGeminiProfile,
      voice: kGeminiProfile.defaultVoice,
    );
    _configService = ConfigService(path: widget.configPath);
    _voiceConfig = _configService.load();
    _inputPath = TextEditingController();
    _voiceRaw = TextEditingController(text: defaults.voice);
    _selectedVoiceLabel = defaults.voice;
    _accent = TextEditingController(text: defaults.accent);
    _style = TextEditingController(text: defaults.style);
    _prefix = TextEditingController(text: defaults.passagePrefix);
    _minWords = TextEditingController(text: defaults.minWords.toString());
    _sampleLen = TextEditingController();
    _outDir = TextEditingController(text: defaults.outDir);
    _apiKey = TextEditingController(text: _voiceConfig.apiKey ?? '');
    _aliasLabel = TextEditingController();
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
      _apiKey,
      _aliasLabel,
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
    final next = profileFor(alias)!;
    setState(() {
      final raw = _voiceRaw.text.trim();
      if (raw.isEmpty || raw == previous.defaultVoice) {
        _voiceRaw.text = next.defaultVoice;
        _selectedVoiceLabel = next.defaultVoice;
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

  /// A draft config read from the form, merging any [extraAliases] into what's
  /// already on disk. The api-key field is the single source of truth for the
  /// stored key (blank clears it).
  VoiceConfig _draftConfig({Map<String, Map<String, String>> extraAliases = const {}}) {
    final aliases = Map<String, Map<String, String>>.from(_voiceConfig.aliases);
    extraAliases.forEach((model, map) {
      final merged = Map<String, String>.from(aliases[model] ?? const {});
      merged.addAll(map);
      if (merged.isNotEmpty) aliases[model] = merged;
    });
    final key = _apiKey.text.trim();
    return VoiceConfig(apiKey: key.isEmpty ? null : key, aliases: aliases);
  }

  void _saveConfig() {
    try {
      _configService.save(_draftConfig());
      setState(() => _voiceConfig = _configService.load());
      _snack('Voice config saved to ${_configService.path}');
    } on VoiceConfigError catch (e) {
      _snack(e.message);
    }
  }

  void _saveAlias() {
    final label = _aliasLabel.text.trim();
    final raw = _voiceRaw.text.trim();
    if (label.isEmpty || raw.isEmpty) {
      _snack('Enter a friendly name and a raw voice id to save an alias.');
      return;
    }
    try {
      _configService.save(_draftConfig(extraAliases: {_modelAlias: {label: raw}}));
      setState(() {
        _voiceConfig = _configService.load();
        _aliasLabel.clear();
        _selectedVoiceLabel = label;
      });
      _snack('Alias "$label" saved for ${_profile.alias}.');
    } on VoiceConfigError catch (e) {
      _snack(e.message);
    }
  }

  NarrationConfig _buildConfig() {
    final inputPath = _inputPath.text.trim();
    var voice = _voiceRaw.text.trim();
    if (voice.isEmpty) voice = _profile.defaultVoice;
    final (voiceId, voiceLabel) = _voiceConfig.resolveVoice(_profile.alias, voice);
    if (!_profile.voiceFreeForm && !_profile.voices.contains(voiceId)) {
      throw FormatException(
        'Unknown voice "$voiceId" for ${_profile.alias}. '
        'Available: ${_profile.voices.join(', ')}',
      );
    }
    final minWords = int.tryParse(_minWords.text.trim()) ?? 30;
    final sampleRaw = _sampleLen.text.trim();
    final keyRaw = _apiKey.text.trim();
    return NarrationConfig(
      inputPath: inputPath,
      profile: _profile,
      voice: voiceId,
      voiceLabel: voiceLabel != voiceId ? voiceLabel : null,
      accent: _accent.text,
      style: _style.text,
      useCalmTag: _useCalmTag,
      passagePrefix: _prefix.text,
      minWords: minWords,
      sampleLen: sampleRaw.isEmpty ? null : int.tryParse(sampleRaw),
      outDir: _outDir.text.trim().isEmpty ? 'output' : _outDir.text.trim(),
      resume: _resume,
      apiKey: keyRaw.isEmpty ? null : keyRaw,
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RunScreen(config: config)),
    );
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
            Text('Model & voice', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: DropdownButton<String>(
                key: const Key('modelDropdown'),
                isExpanded: true,
                value: _modelAlias,
                underline: const SizedBox.shrink(),
                items: [
                  for (final p in kModelProfiles.values)
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
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                            child: Text(
                              e.isAlias ? '${e.label} (alias)' : e.label,
                            ),
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
                        final (id, _) = _voiceConfig
                            .resolveVoice(_profile.alias, _selectedVoiceLabel!);
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
            const SizedBox(height: 8),
            Text('Config', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKey,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'OpenRouter API key (blank = env fallback)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _aliasLabel,
                    decoration: const InputDecoration(
                      labelText: 'Friendly name for the current voice',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _saveAlias,
                  child: const Text('Save alias'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _saveConfig,
                  child: const Text('Save config'),
                ),
              ],
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